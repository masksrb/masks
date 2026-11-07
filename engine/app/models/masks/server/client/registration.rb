module Masks
  module Server
    class Client
      module Registration
        extend ActiveSupport::Concern

        class ScopesUnavailable < StandardError; end
        class EnrollmentRefused < StandardError; end

        included do
          validate :resources_are_named_only_when_approved
        end

        class_methods do
          def register!(metadata)
            new(client_id: SecureRandom.uuid, **registered_attributes(metadata, name: "Unnamed client")).issue_credentials!
          end

          def metadata_attributes(metadata)
            held = metadata.to_h.stringify_keys.compact_blank

            held.slice(*METADATA_STRINGS)
                .merge(held.slice(*METADATA_LISTS).transform_values { |value| Array(value).map(&:to_s) })
                .merge(held.slice(*METADATA_SCOPES).transform_values { |value| Scopes.list(value) })
                .merge(held.slice(*METADATA_FLAGS).transform_values { |value| ActiveModel::Type::Boolean.new.cast(value) })
                .merge(held.key?("client_name") ? { "name" => held["client_name"] } : {})
                .symbolize_keys
          end

          def registered_attributes(metadata, name:, auth_method: DEFAULT_AUTH_METHOD)
            held = metadata_attributes(metadata)
            asked = held[:grant_types].presence || [ "authorization_code" ]
            grant_types = (asked & GRANT_TYPES).presence || asked

            {
              token_endpoint_auth_method: auth_method,
              subject_type: Subjects::PUBLIC,
              application_type: "web"
            }.merge(held).merge(
              name: held[:name] || name,
              grant_types: grant_types,
              response_types: held[:response_types].presence || response_types_for(grant_types),
              allowed_scopes: Scopes.join(declared_scopes(metadata)),
              dynamic: true
            )
          end

          def enroll!(token, metadata)
            app = token.client
            app&.lock!
            refusal = app&.enrollment_refusal(token.scope_list)

            raise EnrollmentRefused, refusal || "the app that issued this enrollment token is gone" if app.nil? || refusal

            held = metadata.to_h.stringify_keys

            raise EnrollmentRefused, "jwks_uri is not accepted here; register the public keys as jwks" if held["jwks_uri"].present?
            raise EnrollmentRefused, "jwks is required: the machine signs in with its own key" if held["jwks"].blank?

            new(
              client_id: SecureRandom.uuid,
              name: held["client_name"].to_s.strip.presence || token.held("name") || "A machine",
              jwks: held["jwks"],
              token_endpoint_auth_method: PRIVATE_KEY_JWT,
              grant_types: [ CLIENT_CREDENTIALS ],
              response_types: [],
              dpop_bound_access_tokens: true,
              resources: app.resources,
              allowed_scopes: Scopes.join(token.scope_list),
              application_type: "native",
              subject_type: Subjects::PUBLIC,
              enrolled_by: app,
              access_token_lifetime: MACHINE_ACCESS_LIFETIME.to_i,
              approved_at: Time.current,
              dynamic: false
            ).issue_credentials!
          end

          def declared_scopes(metadata)
            declared = metadata.to_h.stringify_keys["scope"]

            Scopes.list(declared).empty? ? [] : bounded(declared)
          end

          def bounded(requested)
            reserved = Scopes.reserved(requested) + Scopes.list(requested).select { |s| Scopes.prefix?(s) }

            if reserved.any?
              raise ScopesUnavailable,
                    "#{Scopes.join(reserved.uniq)} may only be granted to an approved client"
            end

            ceiling = Current.tenant&.dynamic_client_ceiling
            bounded = ceiling ? Scopes.granted(requested, ceiling) : Scopes.list(requested)

            if bounded.empty?
              raise ScopesUnavailable,
                    "a dynamically registered client may not request #{Scopes.join(requested)}"
            end

            bounded
          end

          def response_types_for(grant_types)
            (Array(grant_types) & REDIRECTED_GRANT_TYPES).any? ? [ "code" ] : []
          end
        end

        def enrollment_refusal(scopes)
          return "an archived client enrolls nothing" if archived?
          return "a public client enrolls nothing" if public?
          return "only an approved client enrolls machines" unless approved?
          return "a client enrolls machines only after it claims a namespace" if namespaces.empty?
          return "a scope is required" if Scopes.list(scopes).empty?

          held = namespaces.map(&:name)
          outside = Scopes.list(scopes).select do |scope|
            Scopes.prefix?(scope) || scope.start_with?(Scopes::NAMESPACE) || !Scopes.covered?(held, scope)
          end

          "#{Scopes.join(outside)} is outside #{Scopes.join(held)}" if outside.any?
        end

        def enrolled?
          enrolled_by_id.present?
        end

        def unenroll!
          transaction do
            revoked = end_tokens!
            update!(archived_at: Time.current) unless archived?
            revoked
          end
        end

        def follows_registration?
          dynamic? && Scopes.list(allowed_scopes).empty?
        end

        def metadata
          {
            "protocol" => (protocol unless protocol == OIDC),
            "client_id" => client_id,
            "client_name" => name,
            "redirect_uris" => redirect_uris,
            "post_logout_redirect_uris" => post_logout_redirect_uris.presence,
            "grant_types" => grant_types,
            "response_types" => response_types,
            "scope" => Scopes.join(scope_list),
            "token_endpoint_auth_method" => token_endpoint_auth_method,
            "subject_type" => subject_type,
            "dpop_bound_access_tokens" => dpop_bound_access_tokens,
            "sector_identifier_uri" => sector_identifier_uri,
            "application_type" => application_type,
            "client_uri" => client_uri,
            "logo_uri" => logo_uri,
            "tos_uri" => tos_uri,
            "policy_uri" => policy_uri,
            "backchannel_logout_uri" => backchannel_logout_uri,
            "backchannel_logout_session_required" => backchannel_logout_session_required,
            "require_pushed_authorization_requests" => require_pushed_authorization_requests,
            "require_signed_request_object" => require_signed_request_object,
            "jwks" => jwks.presence,
            "jwks_uri" => jwks_uri.presence,
            "authorization_details_types" => authorization_details_types.presence,
            "client_id_issued_at" => created_at&.to_i
          }.compact
        end

        private

          def resources_are_named_only_when_approved
            return unless dynamic? && !approved? && resources.any? && will_save_change_to_resources?

            errors.add(:resources, "may only be named by an approved client, since tokens for a resource are trusted by it")
          end
      end
    end
  end
end
