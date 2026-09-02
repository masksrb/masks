class Provider < ApplicationRecord
  class Unreachable < StandardError; end
  class Refused < StandardError; end

  include TenantScoped

  OPEN_TIMEOUT = 5
  READ_TIMEOUT = 10
  LIMIT = 64.kilobytes

  encrypts :client_secret

  has_many :connections, dependent: :destroy

  validates :key, presence: true,
                  uniqueness: { scope: :tenant_id },
                  format: { with: /\A[a-z0-9][a-z0-9-]*\z/ }
  validates :name, :client_id, presence: true
  validates :authorization_url, :token_url, presence: true

  scope :active, -> { where(archived_at: nil) }

  def scope_list
    Scopes.list(scopes)
  end

  def release_scope
    Scopes.connection(key)
  end

  def archived?
    archived_at.present?
  end

  def authorize_url(redirect_uri:, state:, scopes: nil)
    query = authorize_params.merge(
      "response_type" => "code",
      "client_id" => client_id,
      "redirect_uri" => redirect_uri,
      "scope" => Scopes.join(scopes.presence || scope_list),
      "state" => state
    )

    "#{authorization_url}?#{URI.encode_www_form(query)}"
  end

  def redeem!(code:, redirect_uri:)
    post(token_url,
         grant_type: "authorization_code",
         code: code,
         redirect_uri: redirect_uri)
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

  private

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
      request(url) do |uri|
        Net::HTTP::Get.new(
          uri, "Accept" => "application/json", "Authorization" => "Bearer #{access_token}"
        )
      end
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
