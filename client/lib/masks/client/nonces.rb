module Masks
  module Client
    class Nonces
      HEADER = "DPoP-Nonce".freeze

      def self.origin(url)
        uri = url.is_a?(URI::Generic) ? url : URI.parse(url.to_s)
        port = ":#{uri.port}" unless uri.port.nil? || uri.port == uri.default_port

        "#{uri.scheme.to_s.downcase}://#{uri.host.to_s.downcase}#{port}"
      end

      def initialize
        @held = {}
        @lock = Mutex.new
      end

      def [](url)
        @lock.synchronize { @held[self.class.origin(url)] }
      end

      def learn(url, response)
        wanted = response[HEADER].to_s.strip

        return nil if wanted.empty?

        @lock.synchronize { @held[self.class.origin(url)] = wanted }
      end
    end
  end
end
