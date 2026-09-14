class ClientKeys
  class Refused < StandardError; end

  LIFETIME = 5.minutes
  OPEN_TIMEOUT = 2
  READ_TIMEOUT = 3
  SECRET = %w[d p q dp dq qi k].freeze
  KINDS = %w[RSA EC].freeze

  class << self
    def check!(value)
      held = value.is_a?(String) ? JSON.parse(value) : value
      keys = held.is_a?(Hash) ? held["keys"] : nil

      raise Refused, "must be a JSON Web Key Set with a keys array" unless keys.is_a?(Array) && keys.any?

      keys.each do |key|
        raise Refused, "every key must be a JSON object" unless key.is_a?(Hash)
        raise Refused, "#{key['kty'].presence || 'that'} is not a kind of key a client signs with" unless KINDS.include?(key["kty"])
        raise Refused, "a client's keys must be public" if key.keys.any? { |field| SECRET.include?(field.to_s) }

        JWT::JWK.new(key).verify_key
      end

      held
    rescue JSON::ParserError
      raise Refused, "is not JSON"
    rescue JWT::JWKError, OpenSSL::PKey::PKeyError, ArgumentError => e
      raise Refused, "holds a key that cannot be read: #{e.message}"
    end

    def fetch(uri)
      held = URI.parse(uri.to_s)

      raise Refused, "must be an https URL" unless held.is_a?(URI::HTTPS) || (Rails.env.local? && held.is_a?(URI::HTTP))

      address = Rails.env.local? ? nil : Outbound.vetted(held)

      raise Refused, "resolves to an address this server will not call" unless Rails.env.local? || address

      response = Outbound.get(held, open: OPEN_TIMEOUT, read: READ_TIMEOUT, address: address)

      raise Refused, "answered #{response.code}" unless response.is_a?(Net::HTTPSuccess)

      check!(Outbound.body(response))
    rescue URI::InvalidURIError
      raise Refused, "is not a URI"
    rescue Net::HTTPBadResponse, Net::OpenTimeout, Net::ReadTimeout, SocketError,
           SystemCallError, OpenSSL::SSL::SSLError => e
      raise Refused, "could not be read: #{e.class}"
    end
  end

  attr_reader :client

  def initialize(client)
    @client = client
  end

  def keys(fresh: false)
    return Array(client.jwks&.dig("keys")) if client.jwks.present?
    return [] if client.jwks_uri.blank?

    Rails.cache.delete(cache_key) if fresh

    Array(Rails.cache.fetch(cache_key, expires_in: LIFETIME) { self.class.fetch(client.jwks_uri) }["keys"])
  end

  def remote?
    client.jwks.blank? && client.jwks_uri.present?
  end

  private

    def cache_key
      "client-jwks:#{client.tenant_id}:#{client.id}:#{Digest::SHA256.hexdigest(client.jwks_uri.to_s)}"
    end
end
