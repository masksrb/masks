class Provider < ApplicationRecord
  class Unreachable < StandardError; end
  class Refused < StandardError; end
  class Untrusted < StandardError; end

  include TenantScoped
  include Archivable

  OPEN_TIMEOUT = 5
  READ_TIMEOUT = 10
  LIMIT = 64.kilobytes
  DISCOVERY_PATH = "/.well-known/openid-configuration".freeze

  OIDC = "oidc".freeze
  OAUTH2 = "oauth2".freeze
  SAML = "saml".freeze
  PROTOCOLS = [ OIDC, OAUTH2, SAML ].freeze

  CREDENTIAL = "credential".freeze
  DELEGATE = "delegate".freeze
  ROLES = [ CREDENTIAL, DELEGATE ].freeze

  CLIENT_SECRET_POST = "client_secret_post".freeze
  CLIENT_SECRET_BASIC = "client_secret_basic".freeze
  SIGNED_SECRET = "signed_secret".freeze
  TOKEN_AUTH_METHODS = [ CLIENT_SECRET_POST, CLIENT_SECRET_BASIC, SIGNED_SECRET ].freeze

  FORM_POST = "form_post".freeze
  SIGNED_SECRET_LIFETIME = 5.minutes

  OIDC_SUBJECT_CLAIMS = %w[sub oid].freeze
  MAPPED_CLAIMS = (%w[email email_verified] + Actor::PROFILE_CLAIMS.keys).freeze
  CLAIM_PATH = %r{\A[A-Za-z0-9_:@./#-]{1,256}\z}

  encrypts :client_secret
  encrypts :private_key

  has_many :connections, dependent: :destroy

  validates :key, presence: true,
                  uniqueness: { scope: :tenant_id },
                  format: { with: /\A[a-z0-9][a-z0-9-]*\z/ }
  validates :name, presence: true
  validates :protocol, inclusion: { in: PROTOCOLS }
  validates :role, inclusion: { in: ROLES }
  validates :token_auth_method, inclusion: { in: TOKEN_AUTH_METHODS }
  validates :response_mode, inclusion: { in: [ FORM_POST ] }, allow_nil: true
  validates :client_id, :authorization_url, :token_url, presence: true, unless: :saml?
  validates :idp_entity_id, :idp_sso_url, :idp_certificates, presence: true, if: :saml?
  validates :issuer, presence: true, if: :oidc?
  validates :userinfo_url, presence: true, if: :oauth2?
  validates :subject_claim, format: { with: CLAIM_PATH }
  validates :subject_claim, inclusion: {
    in: OIDC_SUBJECT_CLAIMS,
    message: "must be a claim an issuer never reassigns: #{OIDC_SUBJECT_CLAIMS.join(' or ')}"
  }, if: :oidc?
  validates :team_id, :key_id, :private_key, presence: true, if: :signs_its_secret?
  validate :urls_are_usable
  validate :authorize_params_stay_out_of_the_way
  validate :claims_are_mapped
  validate :private_key_is_usable, if: :signs_its_secret?
  validate :certificates_are_usable, if: :saml?
  validate :signup_scopes_stay_ordinary

  normalizes :issuer, with: ->(value) { value.to_s.strip.chomp("/").presence }
  normalizes :response_mode, with: ->(value) { value.to_s.strip.presence }

  before_validation :name_the_subject, if: :saml?

  URLS = %i[authorization_url token_url userinfo_url emails_url jwks_uri issuer idp_sso_url metadata_url].freeze
  RESERVED_PARAMS = %w[response_type client_id redirect_uri scope state nonce
                       code_challenge code_challenge_method response_mode].freeze

  scope :signing_in, -> { active }

  class << self
    def discover(issuer)
      base = issuer.to_s.strip.chomp("/")

      new(name: base, client_id: "discovery").discover_at(base)
    end
  end

  def discover_at(base)
    uri = URI.parse(base.to_s)

    raise Unreachable, "#{base} is not an absolute URL" unless uri.is_a?(URI::HTTP) && uri.host.present?

    document = get("#{base}#{DISCOVERY_PATH}")

    unless document["issuer"].to_s.chomp("/") == base
      raise Untrusted, "the document at #{base} announces itself as #{document['issuer'].presence || 'nothing'}"
    end

    document
  rescue URI::InvalidURIError
    raise Unreachable, "#{base} is not an absolute URL"
  end

  def federation
    @federation ||= { OIDC => Federation::Oidc, OAUTH2 => Federation::OAuth2, SAML => Federation::Saml }
      .fetch(protocol, Federation::Oidc).new(self)
  end

  def oidc?
    protocol == OIDC
  end

  def oauth2?
    protocol == OAUTH2
  end

  def saml?
    protocol == SAML
  end

  def idp_certificate_list
    idp_certificates.to_s.scan(/-----BEGIN CERTIFICATE-----.+?-----END CERTIFICATE-----/m)
  end

  def refresh_metadata!
    raise Untrusted, "#{name} has no metadata URL" if metadata_url.blank?

    xml = fetch_text(metadata_url, Federation::Saml::METADATA_LIMIT)

    update!(**Federation::Saml.parse_metadata(xml), metadata_fetched_at: Time.current)
  end

  def fetch_text(url, limit)
    uri = URI.parse(url)

    response = Net::HTTP.start(
      uri.hostname, uri.port,
      use_ssl: uri.scheme == "https", open_timeout: OPEN_TIMEOUT, read_timeout: READ_TIMEOUT
    ) { |http| http.request(Net::HTTP::Get.new(uri, "Accept" => "application/samlmetadata+xml, application/xml")) }

    raise Refused, "#{name} answered #{response.code}" unless response.is_a?(Net::HTTPSuccess)
    raise Refused, "#{name} published more than #{limit / 1.kilobyte} KB" if response.body.to_s.bytesize > limit

    response.body.to_s
  rescue Net::HTTPBadResponse, Net::OpenTimeout, Net::ReadTimeout, SocketError, SystemCallError,
         OpenSSL::SSL::SSLError, URI::InvalidURIError => e
    raise Unreachable, "#{name} did not answer: #{e.class}"
  end

  def delegate?
    role == DELEGATE
  end

  def signs_in?
    !archived?
  end

  def signs_its_secret?
    token_auth_method == SIGNED_SECRET
  end

  def form_post?
    response_mode == FORM_POST
  end

  def scope_list
    Scopes.list(scopes)
  end

  def signup_scope_list
    Scopes.list(signup_scopes).presence || Scopes::STANDARD.dup
  end

  def email_domain_list
    email_domains.to_s.downcase.split(/[\s,]+/).reject(&:empty?)
  end

  def welcomes?(email)
    allowed = email_domain_list

    return true if allowed.empty?

    domain = email.to_s.split("@").last.to_s.downcase

    domain.present? && allowed.include?(domain)
  end

  def authoritative_for?(email)
    domain = email.to_s.split("@").last.to_s.downcase

    domain.present? && email_domain_list.include?(domain)
  end

  def vouches_for?(email, verified:)
    return false if email.blank?

    authoritative_for?(email) || (trusts_email && verified)
  end

  def claim_map
    held = claims.is_a?(Hash) ? claims.stringify_keys : {}

    held.merge("sub" => subject_claim)
  end

  def authorize_url(redirect_uri:, state:, scopes: nil, nonce: nil, challenge: nil, prompt: nil)
    query = authorize_params.merge(
      "response_type" => "code",
      "client_id" => client_id,
      "redirect_uri" => redirect_uri,
      "scope" => Scopes.join(scopes.presence || scope_list),
      "state" => state
    )

    query["nonce"] = nonce if nonce.present?
    query["prompt"] = prompt if prompt.present?
    query["response_mode"] = response_mode if form_post?

    if challenge.present?
      query["code_challenge"] = challenge
      query["code_challenge_method"] = "S256"
    end

    separator = authorization_url.to_s.include?("?") ? "&" : "?"

    "#{authorization_url}#{separator}#{URI.encode_www_form(query)}"
  end

  def redeem!(code:, redirect_uri:, verifier: nil)
    post(token_url,
         grant_type: "authorization_code",
         code: code,
         redirect_uri: redirect_uri,
         code_verifier: verifier)
  end

  def get(url, access_token = nil)
    headers = { "Accept" => "application/json" }
    headers["Authorization"] = "Bearer #{access_token}" if access_token.present?

    request(url) { |uri| Net::HTTP::Get.new(uri, headers) }
  end

  def get_list(url, access_token)
    headers = { "Accept" => "application/json", "Authorization" => "Bearer #{access_token}" }

    request(url, list: true) { |uri| Net::HTTP::Get.new(uri, headers) }
  end

  def signed_secret
    now = Time.current.to_i
    key = OpenSSL::PKey.read(private_key.to_s)

    JWT.encode(
      { "iss" => team_id, "iat" => now, "exp" => now + SIGNED_SECRET_LIFETIME.to_i,
        "aud" => issuer, "sub" => client_id },
      key, "ES256", kid: key_id
    )
  end

  private

    def post(url, **params)
      request(url) do |uri|
        Net::HTTP::Post.new(uri, "Accept" => "application/json").tap do |post|
          authenticate(post, params)
        end
      end
    end

    def authenticate(post, params)
      case token_auth_method
      when CLIENT_SECRET_BASIC
        post.basic_auth(URI.encode_www_form_component(client_id), URI.encode_www_form_component(client_secret.to_s))
        post.set_form_data(params.compact)
      when SIGNED_SECRET
        post.set_form_data(params.merge(client_id: client_id, client_secret: signed_secret).compact)
      else
        post.set_form_data(params.merge(client_id: client_id, client_secret: client_secret).compact)
      end
    end

    def request(url, list: false)
      uri = URI.parse(url)

      response = Net::HTTP.start(
        uri.hostname, uri.port,
        use_ssl: uri.scheme == "https",
        open_timeout: OPEN_TIMEOUT,
        read_timeout: READ_TIMEOUT
      ) { |http| http.request(yield(uri)) }

      parsed = parse(response.body)

      raise Refused, upstream_error(parsed, response) unless response.is_a?(Net::HTTPSuccess)

      list ? Array(parsed).grep(Hash) : (parsed.is_a?(Hash) ? parsed : {})
    rescue Net::HTTPBadResponse, Net::OpenTimeout, Net::ReadTimeout, SocketError, SystemCallError,
           OpenSSL::SSL::SSLError, URI::InvalidURIError => e
      raise Unreachable, "#{name} did not answer: #{e.class}"
    end

    def parse(body)
      JSON.parse(body.to_s[0, LIMIT])
    rescue JSON::ParserError
      Rack::Utils.parse_query(body.to_s[0, LIMIT])
    end

    def upstream_error(parsed, response)
      held = parsed.is_a?(Hash) ? parsed : {}
      described = [ held["error"], held["error_description"] ].compact.join(": ")

      described.presence || "#{name} answered #{response.code}"
    end

    def signup_scopes_stay_ordinary
      reserved = Scopes.reserved(signup_scopes)

      return if reserved.empty?

      errors.add(:signup_scopes, "may not hand out #{Scopes.join(reserved)} to an account it creates")
    end

    def urls_are_usable
      URLS.each do |field|
        value = public_send(field)
        next if value.blank?

        uri = usable_uri(value)

        next errors.add(field, "must be an absolute http or https URL") if uri.nil?
        next if uri.scheme == "https" || Client::LOOPBACK.include?(uri.host)

        errors.add(field, "must use https unless it points at a loopback address")
      end
    end

    def authorize_params_stay_out_of_the_way
      held = authorize_params

      return errors.add(:authorize_params, "must be a set of names and values") unless held.is_a?(Hash)

      taken = held.keys.map(&:to_s) & RESERVED_PARAMS

      if taken.any?
        errors.add(:authorize_params, "may not set #{taken.join(', ')} — the request builds those")
      end

      unless held.values.all? { |value| value.is_a?(String) || value.is_a?(Numeric) || [ true, false ].include?(value) }
        errors.add(:authorize_params, "values have to be plain, not nested")
      end
    end

    def claims_are_mapped
      return errors.add(:claims, "must map claims to where the provider puts them") unless claims.is_a?(Hash)

      unknown = claims.keys.map(&:to_s) - MAPPED_CLAIMS
      errors.add(:claims, "cannot map #{unknown.join(', ')}") if unknown.any?

      unless claims.values.all? { |path| path.is_a?(String) && path.match?(CLAIM_PATH) }
        errors.add(:claims, "paths are names separated by dots")
      end
    end

    def name_the_subject
      self.subject_claim = Federation::Saml::NAME_ID if subject_claim.blank? || (new_record? && subject_claim == "sub")
    end

    def certificates_are_usable
      held = idp_certificate_list

      return errors.add(:idp_certificates, "must hold at least one PEM certificate") if held.empty? && idp_certificates.present?

      held.each { |pem| OpenSSL::X509::Certificate.new(pem) }
    rescue OpenSSL::X509::CertificateError
      errors.add(:idp_certificates, "holds a certificate that could not be read")
    end

    def private_key_is_usable
      return if private_key.blank?

      key = OpenSSL::PKey.read(private_key.to_s)

      errors.add(:private_key, "must be an elliptic curve key") unless key.is_a?(OpenSSL::PKey::EC) && key.private?
    rescue OpenSSL::PKey::PKeyError
      errors.add(:private_key, "is not a PEM private key")
    end

    def usable_uri(value)
      uri = URI.parse(value.to_s)

      uri.is_a?(URI::HTTP) && uri.host.present? ? uri : nil
    rescue URI::InvalidURIError
      nil
    end
end
