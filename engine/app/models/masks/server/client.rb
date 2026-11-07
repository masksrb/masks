module Masks
  module Server
    class Client < ApplicationRecord
      include TenantScoped
      include Archivable
      include Paged

      OIDC = "oidc".freeze
      PRIVATE_KEY_JWT = "private_key_jwt".freeze
      SECRET_AUTH_METHODS = %w[client_secret_basic client_secret_post].freeze
      AUTH_METHODS = (SECRET_AUTH_METHODS + [ PRIVATE_KEY_JWT, "none" ]).freeze
      FORWARD = "forward".freeze
      FORWARD_CALLBACK = "/masks-auth/callback".freeze
      ALLOWED_GROUP = /\A[a-z0-9][a-z0-9._-]*(:[a-z0-9._-]+)?\z/
      DEFAULT_AUTH_METHOD = "client_secret_basic".freeze
      CLIENT_CREDENTIALS = "client_credentials".freeze
      REDIRECTED_GRANT_TYPES = %w[authorization_code].freeze
      GRANT_TYPES = [
        "authorization_code",
        "refresh_token",
        CLIENT_CREDENTIALS,
        DeviceGrant::GRANT_TYPE,
        Exchange::GRANT_TYPE
      ].freeze
      RESPONSE_TYPES = %w[code].freeze
      CHALLENGE_METHODS = %w[S256].freeze
      LOOPBACK = %w[localhost 127.0.0.1 ::1].freeze
      DEFAULT_SCOPES = Scopes::STANDARD
      MACHINE_ACCESS_LIFETIME = 10.minutes
      LINKS = %i[client_uri tos_uri policy_uri].freeze
      METADATA_URIS = (LINKS + [ :logo_uri ]).freeze
      URI_LIMIT = 2048
      SCRIPTED_SCHEMES = %w[javascript data vbscript file blob about].freeze
      METADATA_STRINGS = %w[
        token_endpoint_auth_method subject_type sector_identifier_uri application_type client_uri logo_uri tos_uri
        policy_uri backchannel_logout_uri jwks jwks_uri
      ].freeze
      METADATA_LISTS = %w[redirect_uris post_logout_redirect_uris resources authorization_details_types].freeze
      METADATA_SCOPES = %w[grant_types response_types].freeze
      METADATA_FLAGS = %w[
        dpop_bound_access_tokens backchannel_logout_session_required require_pushed_authorization_requests
        require_signed_request_object
      ].freeze
      APPROVED = %i[
        redirect_uris post_logout_redirect_uris token_endpoint_auth_method resources
        subject_type sector_identifier_uri dpop_bound_access_tokens grant_types response_types
        authorization_details_types
      ].freeze
      CONSOLE_ID = "masks-manage".freeze
      CONSOLE_SCOPES = [ Scopes::OPENID, Scopes::PROFILE, Scopes::EMAIL, Scopes::MANAGE, *ManageRoles::SCOPES ].uniq.freeze

      include Registration
      include Credentials
      include Redirects
      include Approval
      include SamlApplication
      include ForwardAuth

      has_many :tokens, dependent: :destroy
      has_many :consents, dependent: :destroy
      has_many :delegations, dependent: :destroy
      has_many :saml_participations, dependent: :delete_all
      has_many :access_requests, dependent: :delete_all
      has_many :namespaces, -> { order(:name) }, dependent: :nullify
      has_many :enrolled, class_name: "Client", foreign_key: :enrolled_by_id, inverse_of: :enrolled_by,
                          dependent: :nullify
      has_one :logo, class_name: "ClientLogo", dependent: :delete

      belongs_to :approved_by, class_name: "Actor", optional: true
      belongs_to :enrolled_by, class_name: "Client", optional: true, inverse_of: :enrolled
      belongs_to :sign_in_policy, optional: true

      validate :allowed_groups_are_named
      validates :client_id, presence: true, uniqueness: { scope: :tenant_id }
      validates :name, presence: true
      validates :token_endpoint_auth_method, inclusion: { in: AUTH_METHODS }
      validates :protocol, inclusion: { in: [ OIDC, SamlIdentity::PROTOCOL, FORWARD ] }
      validates :subject_type, inclusion: { in: Subjects::TYPES }
      validate :grant_types_are_known
      validate :sector_is_derivable
      validate :sector_identifier_uri_is_owned, if: :sector_declared?
      validate :authorization_details_are_declared
      validates :access_token_lifetime, numericality: { only_integer: true, in: 60..1.day.to_i }, allow_nil: true
      validates :refresh_token_lifetime, numericality: { only_integer: true, in: 5.minutes.to_i..400.days.to_i }, allow_nil: true
      validates :refresh_token_absolute_lifetime, numericality: { only_integer: true, in: 5.minutes.to_i..400.days.to_i },
                                                  allow_nil: true
      validates :consent_lifetime, numericality: { only_integer: true, greater_than_or_equal_to: 300,
                                                   less_than_or_equal_to: Consent::LONGEST.to_i }, allow_nil: true

      normalizes :allowed_groups, with: ->(value) { Array(value).map { |group| group.to_s.strip.downcase }.compact_blank.uniq.sort }

      after_commit :refresh_logo!, on: %i[create update], if: :saved_change_to_logo_uri?
      after_update :archived!, if: -> { saved_change_to_archived_at? && archived? }

      scope :speaking, ->(protocol) { active.where(protocol: protocol) }

      def self.authenticating(client_id, protocol: OIDC)
        return ClientMetadataDocument.resolve(client_id.to_s) if protocol == OIDC && ClientMetadataDocument.url?(client_id)

        speaking(protocol).find_by(client_id: client_id.to_s)
      end

      def pairwise?
        subject_type == Subjects::PAIRWISE
      end

      def sector_identifier
        return SectorIdentifier.host(sector_identifier_uri) if sector_identifier_uri.present?

        redirect_hosts.one? ? redirect_hosts.first : nil
      end

      def document?
        metadata_expires_at.present?
      end

      def metadata_stale?
        document? && metadata_expires_at.past?
      end

      def logo_shown_to?(viewer)
        logo_digest.present? && (approved? || viewer&.manages? || false)
      end

      def logo_url(viewer, size: nil)
        return nil unless logo_shown_to?(viewer)

        "#{Current.origin}#{Engine.routes.url_helpers.client_logo_path(client_id, v: logo_digest, size: size)}"
      end

      def refresh_logo!
        ClientLogoJob.perform_later(id)
      end

      def grants?(grant_type)
        grant_types.include?(grant_type.to_s)
      end

      def default_response_types
        self.class.response_types_for(grant_types)
      end

      def unattended_scopes
        Scopes.unattended(scope_list)
      end

      def scope_list
        Scopes.union(required_scopes, offered_scopes)
      end

      def access_lifetime
        access_token_lifetime&.seconds || AccessToken.lifetime
      end

      def refresh_lifetime
        refresh_token_lifetime&.seconds || RefreshToken.lifetime
      end

      def refresh_absolute_lifetime
        refresh_token_absolute_lifetime&.seconds || RefreshToken.absolute_lifetime
      end

      def admits?(actor)
        allowed_groups.empty? || actor.group_labels.intersect?(allowed_groups)
      end

      def permitted_scopes(requested)
        return scope_list if Scopes.list(requested).empty?

        return Scopes.union(required_scopes, unreserved(requested)) if open_to_anything?

        Scopes.union(required_scopes, Scopes.granted(requested, offered_scopes))
      end

      def refused_scopes(requested)
        Scopes.list(requested) - permitted_scopes(requested)
      end

      def offered_scopes
        return Scopes.list(allowed_scopes) unless follows_registration?

        Current.tenant&.dynamic_client_ceiling || DEFAULT_SCOPES
      end

      def end_tokens!
        now = Time.current
        tokens.where(consumed_at: nil).update_all(consumed_at: now, updated_at: now)
      end

      private

        def archived!
          end_tokens!

          machines = enrolled.active.pluck(:id)
          return if machines.empty?

          now = Time.current
          Client.where(id: machines).update_all(archived_at: archived_at, updated_at: now)
          Token.where(client_id: machines, consumed_at: nil).update_all(consumed_at: now, updated_at: now)
        end

        def allowed_groups_are_named
          unknown = allowed_groups.grep_v(ALLOWED_GROUP)

          errors.add(:allowed_groups, "names #{unknown.join(', ')}, which is not a group key or key:role") if unknown.any?
        end

        def open_to_anything?
          follows_registration? && Current.tenant&.dynamic_registration == Tenant::REGISTRATION_ANYTHING
        end

        def unreserved(requested)
          Scopes.list(requested).reject { |scope| Scopes.prefix?(scope) || Scopes.reserved(scope).any? }
        end

        def grant_types_are_known
          unknown = grant_types - GRANT_TYPES
          errors.add(:grant_types, "not supported: #{unknown.join(', ')}") if unknown.any?
        end

        def sector_declared?
          sector_identifier_uri.present? &&
            (sector_identifier_uri_changed? || redirect_uris_changed?)
        end

        def authorization_details_are_declared
          types = authorization_details_types

          unless types.is_a?(Array) && types.size <= 20 && types.all? { |type| type.is_a?(String) && type.match?(AuthorizationDetails::TYPE_FORMAT) }
            errors.add(:authorization_details_types, "must be a list of at most 20 type names")
          end

          return if authorization_details_schemas.blank? || !will_save_change_to_authorization_details_schemas?
          return errors.add(:authorization_details_schemas, "may only be declared by an approved client") unless approved?

          AuthorizationDetails.check_declaration!(authorization_details_schemas)
        rescue AuthorizationDetails::Invalid => e
          errors.add(:authorization_details_schemas, e.message)
        end

        def sector_is_derivable
          return unless pairwise?
          return if sector_identifier.present?

          errors.add(
            :sector_identifier_uri,
            "is required when the redirect URIs do not share one host"
          )
        end

        def sector_identifier_uri_is_owned
          SectorIdentifier.verify!(sector_identifier_uri, redirect_uris)
        rescue SectorIdentifier::Refused => e
          errors.add(:sector_identifier_uri, e.message)
        end
    end
  end
end
