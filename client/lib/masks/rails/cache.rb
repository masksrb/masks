module Masks
  module Rails
    class Cache
      class Unavailable < Masks::Client::Error; end

      CLAIM = 30
      RESULT = 60
      WAIT = 0.05
      PATIENCE = 30
      LOGOUT = 600
      LOGOUT_LEEWAY = 120
      DEPARTURE = 30 * 24 * 3600
      CIPHER = "aes-256-gcm".freeze
      NONCE = 12
      TAG = 16

      def self.key(*parts)
        "masks:#{OpenSSL::Digest::SHA256.hexdigest(parts.map(&:to_s).join("\0"))}"
      end

      def self.now
        (Time.now.to_f * 1000).to_i
      end

      attr_reader :store

      def initialize(store)
        @store = store
      end

      def first?(key, expires_in:)
        add(self.class.key("proof", key), expires_in)
      end

      def first_logout?(issuer, logout)
        add(self.class.key("logout", issuer, logout.jti), logout_memory(logout))
      end

      def depart!(issuer, logout)
        kind, value = logout.sid.to_s.empty? ? [ "sub", logout.subject ] : [ "sid", logout.sid ]

        return if store.write(self.class.key("departed", issuer, kind, value), self.class.now, expires_in: DEPARTURE)

        store.delete(self.class.key("logout", issuer, logout.jti))

        raise Unavailable, "the cache did not keep that logout"
      end

      def departed?(issuer, identity, since:)
        [ [ "sid", identity["sid"] ], [ "sub", identity["sub"] ] ].any? do |kind, value|
          next false if value.to_s.empty?

          at = store.read(self.class.key("departed", issuer, kind, value))

          at.is_a?(Integer) && at >= since
        end
      end

      def renew(issuer, refresh_token)
        result = self.class.key("refreshed", issuer, refresh_token)
        claim = self.class.key("refreshing", issuer, refresh_token)
        found = opened(result, refresh_token)

        return found if found
        return awaited(result, claim, refresh_token) unless add(claim, CLAIM)

        begin
          held = yield

          store.write(result, sealed(refresh_token, held), expires_in: RESULT) unless held.outcome == :unreachable

          held
        ensure
          store.delete(claim)
        end
      end

      private

        def add(key, expires_in)
          store.write(key, 1, unless_exist: true, expires_in: expires_in) ? true : false
        end

        def logout_memory(logout)
          [ LOGOUT, logout.expires_at.to_i - Time.now.to_i + LOGOUT_LEEWAY ].max
        end

        def awaited(result, claim, refresh_token)
          deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + PATIENCE

          while Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline
            sleep WAIT

            found = opened(result, refresh_token)

            return found if found
            return opened(result, refresh_token) || Renewal.unreachable if store.read(claim).nil?
          end

          Renewal.unreachable
        end

        def cipher(mode, refresh_token)
          held = OpenSSL::Cipher.new(CIPHER).public_send(mode)
          held.key = OpenSSL::KDF.hkdf(refresh_token.to_s, salt: "masks", info: "masks/rails shared refresh",
                                                           length: 32, hash: "SHA256")
          held
        end

        def sealed(refresh_token, held)
          plain = JSON.generate(held.to_h)
          sealing = cipher(:encrypt, refresh_token)
          nonce = SecureRandom.random_bytes(NONCE)
          sealing.iv = nonce
          sealing.auth_data = ""
          body = sealing.update(plain) + sealing.final

          Base64.strict_encode64(nonce + sealing.auth_tag(TAG) + body)
        end

        def opened(result, refresh_token)
          held = store.read(result)

          return nil if held.nil?

          raw = Base64.strict_decode64(held.to_s)
          opening = cipher(:decrypt, refresh_token)
          opening.iv = raw.byteslice(0, NONCE)
          opening.auth_tag = raw.byteslice(NONCE, TAG)
          opening.auth_data = ""

          Renewal.from_h(JSON.parse(opening.update(raw.byteslice((NONCE + TAG)..).to_s) + opening.final))
        rescue ArgumentError, TypeError, OpenSSL::Cipher::CipherError, JSON::ParserError
          Renewal.unreachable
        end
    end
  end
end
