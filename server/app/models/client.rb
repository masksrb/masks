class Client < ApplicationRecord
  include TenantScoped

  AUTH_METHODS = %w[client_secret_basic client_secret_post none].freeze
  GRANT_TYPES = [
    "authorization_code",
    "refresh_token",
    Exchange::GRANT_TYPE
  ].freeze
  RESPONSE_TYPES = %w[code].freeze
  CHALLENGE_METHODS = %w[S256].freeze
  LOOPBACK = %w[localhost 127.0.0.1 ::1].freeze
  DEFAULT_SCOPES = Scopes::STANDARD

  class ScopesUnavailable < StandardError; end

  has_many :tokens, dependent: :destroy
  has_many :consents, dependent: :destroy

  validates :client_id, presence: true, uniqueness: { scope: :tenant_id }
  validates :name, presence: true
  validates :token_endpoint_auth_method, inclusion: { in: AUTH_METHODS }
  validate :redirect_uris_are_usable
  validate :grant_types_are_known

  belongs_to :approved_by, class_name: "Actor", optional: true

  scope :active, -> { where(archived_at: nil) }
  scope :approved, -> { where.not(approved_at: nil) }

  attr_reader :secret, :registration_token

  class << self
    def approve!(handshake, actor:)
      client = approved_for(handshake.resource) || new(client_id: SecureRandom.uuid)

      client.assign_attributes(
        name: handshake.name,
        redirect_uris: handshake.redirect_uris,
        resources: [ handshake.resource ],
        allowed_scopes: Scopes.join(handshake.scopes),
        grant_types: Handshake::GRANT_TYPES,
        response_types: [ "code" ],
        token_endpoint_auth_method: "client_secret_basic",
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
      client = new(
        client_id: SecureRandom.uuid,
        name: attributes[:name].presence || "Unnamed client",
        redirect_uris: Array(attributes[:redirect_uris]).map(&:to_s),
        grant_types: Scopes.list(attributes[:grant_types]).presence || [ "authorization_code" ],
        response_types: Scopes.list(attributes[:response_types]).presence || [ "code" ],
        resources: Array(attributes[:resources]).map(&:to_s),
        allowed_scopes: Scopes.join(bounded(attributes[:scopes].presence || DEFAULT_SCOPES)),
        token_endpoint_auth_method: attributes[:token_endpoint_auth_method].presence || "client_secret_basic",
        application_type: attributes[:application_type].presence || "web",
        client_uri: attributes[:client_uri],
        logo_uri: attributes[:logo_uri],
        tos_uri: attributes[:tos_uri],
        policy_uri: attributes[:policy_uri],
        dynamic: true
      )

      client.issue_credentials!
    end

    def bounded(requested)
      ceiling = Current.tenant&.dynamic_client_ceiling
      bounded = ceiling ? Scopes.granted(requested, ceiling) : Scopes.list(requested)

      if bounded.empty?
        raise ScopesUnavailable,
              "a dynamically registered client may not request #{Scopes.join(requested)}"
      end

      bounded
    end

    def authenticating(client_id)
      active.find_by(client_id: client_id.to_s)
    end

    def by_registration_token(token)
      return nil if token.blank?

      active.find_by(registration_token_digest: Digest::SHA256.hexdigest(token.to_s))
    end
  end

  def public?
    token_endpoint_auth_method == "none"
  end

  def approved?
    approved_at.present?
  end

  def issue_credentials!
    issue_secret! unless public?
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

  def scope_list
    Scopes.union(required_scopes, allowed_scopes)
  end

  def permitted_scopes(requested)
    return scope_list if Scopes.list(requested).empty?

    Scopes.union(required_scopes, Scopes.granted(requested, allowed_scopes))
  end

  def metadata
    {
      "client_id" => client_id,
      "client_name" => name,
      "redirect_uris" => redirect_uris,
      "grant_types" => grant_types,
      "response_types" => response_types,
      "scope" => Scopes.join(scope_list),
      "token_endpoint_auth_method" => token_endpoint_auth_method,
      "application_type" => application_type,
      "client_uri" => client_uri,
      "logo_uri" => logo_uri,
      "tos_uri" => tos_uri,
      "policy_uri" => policy_uri,
      "client_id_issued_at" => created_at&.to_i
    }.compact
  end

  private

    def redirect_uris_are_usable
      if redirect_uris.blank?
        errors.add(:redirect_uris, "must include at least one URI")
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
end
