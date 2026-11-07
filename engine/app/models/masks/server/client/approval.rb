module Masks
  module Server
    class Client
      module Approval
        extend ActiveSupport::Concern

        included do
          validate :consent_is_skipped_only_when_approved

          scope :approved, -> { where.not(approved_at: nil) }
        end

        class_methods do
          def console!(issuer)
            approved_for(issuer.manage_resource) || create!(
              client_id: CONSOLE_ID,
              name: "Manage #{Current.tenant.name}",
              redirect_uris: [ "#{issuer.manage_resource}/callback" ],
              post_logout_redirect_uris: [ issuer.manage_resource ],
              resources: [ issuer.manage_resource ],
              allowed_scopes: Scopes.join(CONSOLE_SCOPES),
              grant_types: %w[authorization_code refresh_token],
              response_types: [ "code" ],
              token_endpoint_auth_method: "none",
              client_uri: issuer.url,
              handshake_return_to: issuer.manage_resource,
              consent_required: false,
              dynamic: false,
              approved_at: Time.current
            )
          rescue ActiveRecord::RecordNotUnique
            find_by!(client_id: CONSOLE_ID)
          end

          def approve!(handshake, actor:)
            client = approved_for(handshake.resource) || new(client_id: SecureRandom.uuid)

            client.assign_attributes(
              described_by(handshake).merge(approved_at: Time.current, approved_by: actor, archived_at: nil)
            )

            client.save!
            client
          end

          def described_by(handshake)
            {
              name: handshake.name,
              redirect_uris: handshake.redirect_uris,
              post_logout_redirect_uris: [ handshake.post_logout_redirect_uri ].compact,
              resources: [ handshake.resource ],
              allowed_scopes: Scopes.join(handshake.scopes),
              grant_types: handshake.grant_types,
              response_types: [ "code" ],
              token_endpoint_auth_method: handshake.auth_method,
              backchannel_logout_uri: handshake.backchannel_logout_uri,
              client_uri: handshake.origin,
              handshake_return_to: handshake.return_to,
              dynamic: false
            }
          end

          def approved_for(resource)
            return nil if resource.blank?

            active.approved.where(enrolled_by_id: nil).where("resources @> ?", [ resource.to_s ].to_json).first
          end
        end

        def approved?
          approved_at.present?
        end

        def approved_as?(handshake)
          described = self.class.described_by(handshake)
          candidate = self.class.new(described)

          described.keys.all? { |key| public_send(key) == candidate.public_send(key) }
        end

        private

          def consent_is_skipped_only_when_approved
            return if consent_required? || approved?

            errors.add(:consent_required, "may only be switched off for an approved client")
          end
      end
    end
  end
end
