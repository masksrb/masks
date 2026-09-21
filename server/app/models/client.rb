class Client < ApplicationRecord
  include TenantScoped
  include Archivable
  include Paged

  OIDC = "oidc".freeze
  PRIVATE_KEY_JWT = "private_key_jwt".freeze
  SECRET_AUTH_METHODS = %w[client_secret_basic client_secret_post].freeze
  AUTH_METHODS = (SECRET_AUTH_METHODS + [ PRIVATE_KEY_JWT, "none" ]).freeze
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
  METADATA_URIS = %i[client_uri logo_uri tos_uri policy_uri].freeze
  METADATA_URI_LIMIT = 2048

  class ScopesUnavailable < StandardError; end

  has_many :tokens, dependent: :destroy
  has_many :consents, dependent: :destroy
  has_many :delegations, dependent: :destroy
  has_many :namespaces, -> { order(:name) }, dependent: :nullify
  has_one :logo, class_name: "ClientLogo", dependent: :delete

  validates :client_id, presence: true, uniqueness: { scope: :tenant_id }
  validates :name, presence: true
  validates :token_endpoint_auth_method, inclusion: { in: AUTH_METHODS }
  validates :protocol, inclusion: { in: [ OIDC, SamlIdentity::PROTOCOL ] }
  validates :saml_entity_id, uniqueness: { scope: :tenant_id }, allow_nil: true
  validates :subject_type, inclusion: { in: Subjects::TYPES }
  validate :redirect_uris_are_usable
  validate :grant_types_are_known
  validate :client_credentials_are_confidential
  validate :keys_are_usable
  validate :saml_is_described, if: :saml?
  validate :backchannel_logout_uri_is_usable
  validate :sector_is_derivable
  validate :consent_is_skipped_only_when_approved
  validate :sector_identifier_uri_is_owned, if: :sector_declared?
  validate :metadata_uris_are_usable

  normalizes :saml_entity_id, with: ->(value) { value.to_s.strip.presence }
  normalizes(*METADATA_URIS, with: ->(value) { value.to_s.strip.presence })

  after_commit :fetch_logo, on: %i[create update], if: :saved_change_to_logo_uri?

  belongs_to :approved_by, class_name: "Actor", optional: true
  belongs_to :sign_in_policy, optional: true

  scope :approved, -> { where.not(approved_at: nil) }
  scope :speaking, ->(protocol) { active.where(protocol: protocol) }

  attr_reader :secret, :registration_token

  class << self
    def approve!(handshake, actor:)
      client = approved_for(handshake.resource) || new(client_id: SecureRandom.uuid)

      client.assign_attributes(
        name: handshake.name,
        redirect_uris: handshake.redirect_uris,
        post_logout_redirect_uris: [ handshake.return_to ].compact,
        resources: [ handshake.resource ],
        allowed_scopes: Scopes.join(handshake.scopes),
        grant_types: handshake.grant_types,
        response_types: [ "code" ],
        token_endpoint_auth_method: handshake.auth_method,
        backchannel_logout_uri: handshake.backchannel_logout_uri,
        client_uri: handshake.origin,
        dynamic: false,
        approved_at: Time.current,
        approved_by: actor,
        archived_at: nil
      )

      client.save!
      client
    end

    def approved_for(resource)
      return nil if resource.blank?

      active.approved.where("resources @> ?", [ resource.to_s ].to_json).first
    end

    def register!(attributes)
      grant_types = Scopes.list(attributes[:grant_types]).presence || [ "authorization_code" ]

      client = new(
        client_id: SecureRandom.uuid,
        name: attributes[:name].presence || "Unnamed client",
        redirect_uris: Array(attributes[:redirect_uris]).map(&:to_s),
        post_logout_redirect_uris: Array(attributes[:post_logout_redirect_uris]).map(&:to_s),
        grant_types: grant_types,
        response_types: Scopes.list(attributes[:response_types]).presence || response_types_for(grant_types),
        resources: Array(attributes[:resources]).map(&:to_s),
        allowed_scopes: Scopes.join(bounded(attributes[:scopes].presence || DEFAULT_SCOPES)),
        token_endpoint_auth_method: attributes[:token_endpoint_auth_method].presence || DEFAULT_AUTH_METHOD,
        subject_type: attributes[:subject_type].presence || Subjects::PUBLIC,
        dpop_bound_access_tokens:
          ActiveModel::Type::Boolean.new.cast(attributes[:dpop_bound_access_tokens]) || false,
        sector_identifier_uri: attributes[:sector_identifier_uri],
        application_type: attributes[:application_type].presence || "web",
        client_uri: attributes[:client_uri],
        logo_uri: attributes[:logo_uri],
        tos_uri: attributes[:tos_uri],
        policy_uri: attributes[:policy_uri],
        backchannel_logout_uri: attributes[:backchannel_logout_uri],
        backchannel_logout_session_required:
          ActiveModel::Type::Boolean.new.cast(attributes[:backchannel_logout_session_required]) || false,
        require_pushed_authorization_requests:
          ActiveModel::Type::Boolean.new.cast(attributes[:require_pushed_authorization_requests]) || false,
        jwks: attributes[:jwks],
        jwks_uri: attributes[:jwks_uri],
        require_signed_request_object:
          ActiveModel::Type::Boolean.new.cast(attributes[:require_signed_request_object]) || false,
        dynamic: true
      )

      client.issue_credentials!
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

    def authenticating(client_id, protocol: OIDC)
      speaking(protocol).find_by(client_id: client_id.to_s)
    end

    def saml_for(entity_id)
      speaking(SamlIdentity::PROTOCOL).find_by(saml_entity_id: entity_id.to_s)
    end

    def by_registration_token(token)
      return nil if token.blank?

      active.find_by(registration_token_digest: Digest::SHA256.hexdigest(token.to_s))
    end
  end

  def public?
    token_endpoint_auth_method == "none"
  end

  def asserts?
    token_endpoint_auth_method == PRIVATE_KEY_JWT
  end

  def secret?
    SECRET_AUTH_METHODS.include?(token_endpoint_auth_method)
  end

  def pairwise?
    subject_type == Subjects::PAIRWISE
  end

  def sector_identifier
    return SectorIdentifier.host(sector_identifier_uri) if sector_identifier_uri.present?

    redirect_hosts.one? ? redirect_hosts.first : nil
  end

  def redirect_hosts
    redirect_uris.filter_map { |value| SectorIdentifier.host(value) }.uniq
  end

  def approved?
    approved_at.present?
  end

  def shown_logo
    logo if approved?
  end

  def logo_url(origin = Current.origin, shown: approved?)
    return nil unless shown

    digest = ClientLogo.where(client_id: id).pick(:digest)

    digest && "#{origin}/clients/#{client_id}/logo?v=#{digest}"
  end

  def issue_credentials!
    issue_secret! if secret?
    issue_registration_token!
    save!
    self
  end

  def issue_secret!
    @secret = SecureRandom.urlsafe_base64(48)
    self.secret_digest = BCrypt::Password.create(@secret)
    @secret
  end

  def issue_registration_token!
    @registration_token = SecureRandom.urlsafe_base64(48)
    self.registration_token_digest = Digest::SHA256.hexdigest(@registration_token)
    @registration_token
  end

  def authenticate_secret(candidate)
    return true if public?
    return false unless secret?
    return false if secret_digest.blank? || candidate.blank?

    BCrypt::Password.new(secret_digest) == candidate.to_s
  rescue BCrypt::Errors::InvalidHash
    false
  end

  def redirect_uri?(candidate)
    redirect_uris.include?(candidate.to_s)
  end

  def grants?(grant_type)
    grant_types.include?(grant_type.to_s)
  end

  def redirects?
    saml? || (grant_types & REDIRECTED_GRANT_TYPES).any?
  end

  def saml?
    protocol == SamlIdentity::PROTOCOL
  end

  def keys?
    jwks.present? || jwks_uri.present?
  end

  def default_response_types
    self.class.response_types_for(grant_types)
  end

  def saml_x509_certificate
    return nil if saml_certificate.blank?

    OpenSSL::X509::Certificate.new(OneLogin::RubySaml::Utils.format_cert(saml_certificate.to_s.strip))
  rescue OpenSSL::X509::CertificateError
    nil
  end

  def unattended_scopes
    Scopes.unattended(scope_list)
  end

  def scope_list
    Scopes.union(required_scopes, allowed_scopes)
  end

  def permitted_scopes(requested)
    return scope_list if Scopes.list(requested).empty?

    Scopes.union(required_scopes, Scopes.granted(requested, allowed_scopes))
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
      "client_id_issued_at" => created_at&.to_i
    }.compact
  end

  def notified_on_logout?
    backchannel_logout_uri.present?
  end

  private

    def consent_is_skipped_only_when_approved
      return if consent_required? || approved?

      errors.add(:consent_required, "may only be switched off for an approved client")
    end

    def backchannel_logout_uri_is_usable
      return if backchannel_logout_uri.blank?

      uri = URI.parse(backchannel_logout_uri.to_s)

      if uri.fragment.present?
        errors.add(:backchannel_logout_uri, "must not contain a fragment")
      elsif uri.scheme.blank? || uri.host.blank?
        errors.add(:backchannel_logout_uri, "must be absolute")
      elsif !uri.is_a?(URI::HTTP)
        errors.add(:backchannel_logout_uri, "must be an http or https URL")
      elsif dynamic? && !Rails.env.local?
        errors.add(:backchannel_logout_uri, "must use https") unless uri.scheme == "https"
        errors.add(:backchannel_logout_uri, "must not point at a loopback address") if loopback?(uri)
      elsif uri.scheme == "http" && !loopback?(uri) && !Rails.env.local?
        errors.add(:backchannel_logout_uri, "must use https unless it is loopback")
      end
    rescue URI::InvalidURIError
      errors.add(:backchannel_logout_uri, "is not a URI")
    end

    def redirect_uris_are_usable
      if redirect_uris.blank?
        errors.add(:redirect_uris, "must include at least one URI") if redirects?
        return
      end

      redirect_uris.each do |value|
        uri = URI.parse(value.to_s)

        if uri.fragment.present?
          errors.add(:redirect_uris, "must not contain a fragment: #{value}")
        elsif uri.scheme.blank?
          errors.add(:redirect_uris, "must be absolute: #{value}")
        elsif uri.scheme == "http" && !loopback?(uri) && !Rails.env.local?
          errors.add(:redirect_uris, "must use https unless it is loopback: #{value}")
        end
      rescue URI::InvalidURIError
        errors.add(:redirect_uris, "is not a URI: #{value}")
      end
    end

    def loopback?(uri)
      host = uri.host.to_s

      LOOPBACK.include?(host) || host.end_with?(".localhost")
    end

    def grant_types_are_known
      unknown = grant_types - GRANT_TYPES
      errors.add(:grant_types, "not supported: #{unknown.join(', ')}") if unknown.any?
    end

    def saml_is_described
      errors.add(:saml_entity_id, "is required for a SAML application") if saml_entity_id.blank?
      errors.add(:grant_types, "are not used by a SAML application") if grant_types.any?
      errors.add(:token_endpoint_auth_method, "is none for a SAML application") unless public?
      errors.add(:saml_certificate, "is not a certificate masks can read") if saml_certificate.present? && saml_x509_certificate.nil?
      errors.add(:saml_certificate, "is required to check signed requests") if saml_requests_signed? && saml_certificate.blank?

      if saml_name_id_format.present? && !SamlIdentity::NAME_ID_FORMATS.include?(saml_name_id_format)
        errors.add(:saml_name_id_format, "is not one masks issues")
      end

      unless saml_attributes.is_a?(Hash) && saml_attributes.all? { |name, claim| name.to_s.match?(/\A[\w:.\/-]{1,256}\z/) && claim.is_a?(String) }
        errors.add(:saml_attributes, "map attribute names to claim names")
      end
    end

    def client_credentials_are_confidential
      return unless grants?(CLIENT_CREDENTIALS)

      errors.add(:grant_types, "client_credentials needs a client that authenticates, not a public one") if public?
      errors.add(:grant_types, "client_credentials may only be granted to an approved client") unless approved?
    end

    def keys_are_usable
      errors.add(:jwks, "and jwks_uri cannot both be registered") if jwks.present? && jwks_uri.present?

      if require_signed_request_object? && !keys?
        errors.add(:require_signed_request_object, "needs jwks or a jwks_uri to check request objects against")
      end

      if asserts? && !keys?
        errors.add(:token_endpoint_auth_method, "private_key_jwt needs jwks or a jwks_uri to check assertions against")
      end

      self.jwks = ClientKeys.check!(jwks) if jwks.present? && will_save_change_to_jwks?
      ClientKeys.fetch(jwks_uri) if jwks_uri.present? && will_save_change_to_jwks_uri?
    rescue ClientKeys::Refused => e
      errors.add(jwks_uri.present? && jwks.blank? ? :jwks_uri : :jwks, e.message)
    end

    def sector_declared?
      sector_identifier_uri.present? &&
        (sector_identifier_uri_changed? || redirect_uris_changed?)
    end

    def metadata_uris_are_usable
      METADATA_URIS.each do |field|
        value = public_send(field)

        next if value.blank? || !will_save_change_to_attribute?(field)

        refusal = metadata_uri_refusal(value)
        errors.add(field, refusal) if refusal
      end
    end

    def metadata_uri_refusal(value)
      return "must be at most #{METADATA_URI_LIMIT} characters" if value.length > METADATA_URI_LIMIT

      uri = URI.parse(value)

      if !uri.is_a?(URI::HTTP) || uri.host.blank?
        "must be an http or https URL"
      elsif uri.userinfo.present?
        "must not carry a username or password"
      elsif uri.scheme == "http" && !loopback?(uri) && !Rails.env.local?
        "must use https unless it is loopback"
      end
    rescue URI::InvalidURIError
      "is not a URI"
    end

    def fetch_logo
      ClientLogoJob.perform_later(id)
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
