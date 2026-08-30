module Masks
  module Client
    class Registry
      def initialize
        @issuers = {}
        @lock = Mutex.new
      end

      def [](url, ttl: Issuer::TTL)
        key = Issuer.normalize(url)

        @lock.synchronize { @issuers[key] ||= Issuer.new(key, ttl: ttl) }
      end

      def clear!
        @lock.synchronize { @issuers.clear }
        self
      end

      def urls
        @lock.synchronize { @issuers.keys }
      end
    end
  end
end
