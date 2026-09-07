module SectorIdentifier
  class Refused < StandardError; end

  OPEN_TIMEOUT = 2
  READ_TIMEOUT = 3

  class << self
    def verify!(uri, redirect_uris)
      held = parse(uri)

      raise Refused, "must be an https URL" unless held.is_a?(URI::HTTPS)

      unless Rails.env.local? || Outbound.routable?(held)
        raise Refused, "resolves to an address this server will not call"
      end

      missing = Array(redirect_uris).map(&:to_s) - declared(held)

      raise Refused, "does not list #{missing.join(', ')}" if missing.any?

      true
    end

    def host(value)
      URI.parse(value.to_s).host&.downcase.presence
    rescue URI::InvalidURIError
      nil
    end

    private

      def parse(value)
        URI.parse(value.to_s)
      rescue URI::InvalidURIError
        raise Refused, "is not a URI"
      end

      def declared(uri)
        response = Outbound.get(uri, open: OPEN_TIMEOUT, read: READ_TIMEOUT)

        raise Refused, "answered #{response.code}" unless response.is_a?(Net::HTTPSuccess)

        held = JSON.parse(Outbound.body(response))

        raise Refused, "must hold a JSON array of redirect URIs" unless held.is_a?(Array)

        held.map(&:to_s)
      rescue JSON::ParserError
        raise Refused, "did not answer with JSON"
      rescue Net::HTTPBadResponse, Net::OpenTimeout, Net::ReadTimeout, SocketError,
             SystemCallError, OpenSSL::SSL::SSLError => e
        raise Refused, "could not be read: #{e.class}"
      end
  end
end
