class Handshake
  GRANT_TYPES = %w[authorization_code refresh_token].freeze

  attr_reader :name, :redirect_uris, :resource, :scopes, :return_to, :state

  class << self
    def from_request(request)
      repeated = Rack::Utils.parse_query(request.query_string)
      params = request.params

      new(
        name: params["client_name"],
        redirect_uris: repeated["redirect_uris"] || params["redirect_uris"],
        resource: params["resource"],
        scopes: params["scope"],
        return_to: params["return_to"],
        state: params["state"]
      )
    end

    def from_session(data)
      return nil if data.blank?

      new(**data.symbolize_keys)
    end
  end

  def initialize(name: nil, redirect_uris: nil, resource: nil, scopes: nil,
                 return_to: nil, state: nil)
    @name = name.to_s.strip.presence || "An application"
    @redirect_uris = Array(redirect_uris).map(&:to_s).reject(&:empty?).uniq
    @resource = resource.to_s
    @scopes = Scopes.list(scopes)
    @return_to = return_to.to_s
    @state = state.presence
  end

  def to_session
    {
      "name" => name,
      "redirect_uris" => redirect_uris,
      "resource" => resource,
      "scopes" => scopes,
      "return_to" => return_to,
      "state" => state
    }
  end

  def origin
    @origin ||= origin_of(resource)
  end

  def usable?
    refusal.nil?
  end

  def refusal
    return @refusal if defined?(@refusal)

    @refusal = check
  end

  def approved(secret, issuer:)
    answer("initial_access_token" => secret, "iss" => issuer)
  end

  def declined
    answer(
      "error" => "access_denied",
      "error_description" => "the person signing in declined"
    )
  end

  private

    def check
      return "a resource is required" if resource.blank?
      return "the resource must be an absolute https URL" if origin.nil?
      return "at least one redirect_uris is required" if redirect_uris.empty?
      return "a return_to is required" if return_to.blank?
      return "a scope is required" if scopes.empty?

      elsewhere = ([ return_to ] + redirect_uris).reject { |uri| origin_of(uri) == origin }
      return "everything must share the origin #{origin}: #{elsewhere.join(', ')}" if elsewhere.any?

      nil
    end

    def answer(pairs)
      uri = URI.parse(return_to)
      query = Rack::Utils.parse_query(uri.query).merge(pairs)
      query["state"] = state if state

      uri.query = Rack::Utils.build_query(query)
      uri.to_s
    end

    def origin_of(value)
      uri = URI.parse(value.to_s)

      return nil if uri.host.blank? || uri.fragment.present?
      return nil unless uri.scheme == "https" || http?(uri)

      port = ":#{uri.port}" unless uri.port == uri.default_port
      "#{uri.scheme}://#{uri.host}#{port}"
    rescue URI::InvalidURIError
      nil
    end

    def http?(uri)
      return false unless uri.scheme == "http"

      Rails.env.local? || Client::LOOPBACK.include?(uri.host) || uri.host.end_with?(".localhost")
    end
end
