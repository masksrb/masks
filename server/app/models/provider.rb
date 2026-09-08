class Provider < ApplicationRecord
  class Unreachable < StandardError; end
  class Refused < StandardError; end
  class Untrusted < StandardError; end

  include TenantScoped

  OPEN_TIMEOUT = 5
  READ_TIMEOUT = 10
  LIMIT = 64.kilobytes
  SKEW = 60
  JWKS_INTERVAL = 5.minutes
  DISCOVERY_PATH = "/.well-known/openid-configuration".freeze
  ALGORITHMS = %w[RS256 RS384 RS512 ES256 ES384 ES512 PS256 PS384 PS512].freeze
  SUBJECT_CLAIMS = %w[sub oid].freeze

  encrypts :client_secret

  has_many :connections, dependent: :destroy

  validates :key, presence: true,
                  uniqueness: { scope: :tenant_id },
                  format: { with: /\A[a-z0-9][a-z0-9-]*\z/ }
  validates :name, :client_id, presence: true
  validates :authorization_url, :token_url, presence: true
  validates :subject_claim, inclusion: {
    in: SUBJECT_CLAIMS,
    message: "must be a claim an issuer never reassigns: #{SUBJECT_CLAIMS.join(' or ')}"
  }
  validate :urls_are_usable
  validate :authorize_params_stay_out_of_the_way
  validate :signing_in_needs_an_issuer
  validate :signup_scopes_stay_ordinary

  normalizes :issuer, with: ->(value) { value.to_s.strip.chomp("/").presence }

  URLS = %i[authorization_url token_url revocation_url userinfo_url].freeze
  ISSUED_URLS = (URLS + %i[jwks_uri issuer]).freeze
  RESERVED_PARAMS = %w[response_type client_id redirect_uri scope state nonce
                       code_challenge code_challenge_method].freeze

  scope :active, -> { where(archived_at: nil) }
  scope :signing_in, -> { active.where(signs_in: true).where.not(issuer: nil) }

  class << self
    def discover(issuer)
      base = issuer.to_s.strip.chomp("/")

      new(name: base, client_id: "discovery").discover_at(base)
    end
  end

  def discover_at(base)
    uri = URI.parse(base.to_s)

    raise Unreachable, "#{base} is not an absolute URL" unless uri.is_a?(URI::HTTP) && uri.host.present?

    document = get("#{base}#{DISCOVERY_PATH}", nil)

    unless document["issuer"].to_s.chomp("/") == base
      raise Untrusted, "the document at #{base} announces itself as #{document['issuer'].presence || 'nothing'}"
    end

    document
  rescue URI::InvalidURIError
    raise Unreachable, "#{base} is not an absolute URL"
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

  def release_scope
    Scopes.connection(key)
  end

  def archived?
    archived_at.present?
  end

  def signs_in?
    signs_in && issuer.present? && !archived?
  end

  def sign_in_scopes
    Scopes.union(%w[openid email profile], scope_list)
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

    if challenge.present?
      query["code_challenge"] = challenge
      query["code_challenge_method"] = "S256"
    end

    "#{authorization_url}?#{URI.encode_www_form(query)}"
  end

  def redeem!(code:, redirect_uri:, verifier: nil)
    post(token_url,
         grant_type: "authorization_code",
         code: code,
         redirect_uri: redirect_uri,
         code_verifier: verifier)
  end

  def refresh!(refresh_token)
    post(token_url,
         grant_type: "refresh_token",
         refresh_token: refresh_token)
  end

  def revoke!(token)
    return false if revocation_url.blank? || token.blank?

    post(revocation_url, token: token)
    true
  rescue Refused, Unreachable
    false
  end

  def identify(access_token)
    return {} if userinfo_url.blank?

    get(userinfo_url, access_token)
  end

  def assert!(tokens, nonce:)
    raise Untrusted, "#{name} returned no id_token" if tokens["id_token"].blank?

    claims = verify(tokens["id_token"])

    raise Untrusted, "#{name} answered for #{claims['iss']}, not #{issuer}" unless claims["iss"].to_s.chomp("/") == issuer
    raise Untrusted, "#{name} issued that token to another application" unless audience_holds?(claims)
    raise Untrusted, "#{name} returned a token for a different sign-in" unless nonce.present? && claims["nonce"] == nonce
    raise Untrusted, "#{name} returned no subject" if claims["sub"].blank?

    fill(claims, tokens)
  end

  def refresh_keys!
    document = jwks_uri.presence ? nil : self.class.discover(issuer)
    endpoint = jwks_uri.presence || document["jwks_uri"]

    raise Untrusted, "#{name} publishes no jwks_uri" if endpoint.blank?

    fetched = get(endpoint, nil)

    raise Untrusted, "#{name} published no keys" unless fetched["keys"].is_a?(Array) && fetched["keys"].any?

    update!(jwks: fetched, jwks_uri: endpoint, jwks_fetched_at: Time.current)

    fetched
  end

  private

    def audience_holds?(claims)
      audience = Array(claims["aud"])

      return false unless audience.include?(client_id)
      return true if audience.length == 1

      claims["azp"].present? ? claims["azp"] == client_id : false
    end

    def fill(claims, tokens)
      return claims if userinfo_url.blank? || claims["email"].present?

      profile = identify(tokens["access_token"]).except("iss", "aud", "exp", "iat", "nonce")

      return claims unless profile["sub"].present? && profile["sub"] == claims["sub"]

      profile.merge(claims)
    rescue Refused, Unreachable
      claims
    end

    def verify(id_token)
      keys = held_keys
      kid = peek(id_token)["kid"]

      keys = refresh_keys! if stale_keys?(keys, kid)

      decode(id_token, keys)
    rescue JWT::VerificationError, JWT::DecodeError => e
      raise Untrusted, "#{name} signed that token with a key this server could not verify (#{e.class})"
    end

    def decode(id_token, keys)
      JWT.decode(
        id_token, nil, true,
        algorithms: ALGORITHMS,
        jwks: JWT::JWK::Set.new(keys),
        verify_expiration: true,
        verify_iat: true,
        exp_leeway: SKEW,
        iat_leeway: SKEW,
        nbf_leeway: SKEW
      ).first
    end

    def held_keys
      held = jwks.is_a?(Hash) ? jwks : {}

      held["keys"].is_a?(Array) ? held : { "keys" => [] }
    end

    def stale_keys?(keys, kid)
      return false if jwks_fetched_at.present? && jwks_fetched_at > JWKS_INTERVAL.ago && keys["keys"].any?
      return true if keys["keys"].empty?

      kid.blank? || keys["keys"].none? { |key| key["kid"] == kid }
    end

    def peek(id_token)
      header = id_token.to_s.split(".").first

      JSON.parse(Base64.urlsafe_decode64(header.to_s + "=" * ((4 - header.to_s.length % 4) % 4)))
    rescue ArgumentError, JSON::ParserError
      {}
    end

    def signing_in_needs_an_issuer
      return unless signs_in

      errors.add(:issuer, "is needed before this provider can sign anybody in") if issuer.blank?
    end

    def signup_scopes_stay_ordinary
      reserved = Scopes.reserved(signup_scopes)

      return if reserved.empty?

      errors.add(:signup_scopes, "may not hand out #{Scopes.join(reserved)} to an account it creates")
    end

    def urls_are_usable
      ISSUED_URLS.each do |field|
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

    def usable_uri(value)
      uri = URI.parse(value.to_s)

      uri.is_a?(URI::HTTP) && uri.host.present? ? uri : nil
    rescue URI::InvalidURIError
      nil
    end

    def post(url, **params)
      request(url) do |uri|
        Net::HTTP::Post.new(uri, "Accept" => "application/json").tap do |post|
          post.set_form_data(
            params.merge(client_id: client_id, client_secret: client_secret).compact
          )
        end
      end
    end

    def get(url, access_token)
      headers = { "Accept" => "application/json" }
      headers["Authorization"] = "Bearer #{access_token}" if access_token.present?

      request(url) { |uri| Net::HTTP::Get.new(uri, headers) }
    end

    def request(url)
      uri = URI.parse(url)

      response = Net::HTTP.start(
        uri.hostname, uri.port,
        use_ssl: uri.scheme == "https",
        open_timeout: OPEN_TIMEOUT,
        read_timeout: READ_TIMEOUT
      ) { |http| http.request(yield(uri)) }

      parsed = parse(response.body)

      unless response.is_a?(Net::HTTPSuccess)
        raise Refused, upstream_error(parsed, response)
      end

      parsed
    rescue Net::HTTPBadResponse, Net::OpenTimeout, Net::ReadTimeout, SocketError, SystemCallError,
           OpenSSL::SSL::SSLError, URI::InvalidURIError => e
      raise Unreachable, "#{name} did not answer: #{e.class}"
    end

    def parse(body)
      parsed = JSON.parse(body.to_s[0, LIMIT])
      parsed.is_a?(Hash) ? parsed : {}
    rescue JSON::ParserError
      {}
    end

    def upstream_error(parsed, response)
      described = [ parsed["error"], parsed["error_description"] ].compact.join(": ")

      described.presence || "#{name} answered #{response.code}"
    end
end
