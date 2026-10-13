require "zlib"

module Masks
  module Rails
    class SessionCookies
      class Overflow < Masks::Client::Error; end

      VERSION = "v1".freeze
      PIECE = 3800
      PIECES = 8
      CIPHER = "aes-256-gcm".freeze
      NONCE = 12
      TAG = 16
      PURPOSE = "masks session cookie".freeze
      UNPACKED = PIECE * PIECES * 8

      class << self
        def seal(held, bound)
          sealing = OpenSSL::Cipher.new(CIPHER).encrypt
          sealing.key = key
          nonce = SecureRandom.random_bytes(NONCE)
          sealing.iv = nonce
          sealing.auth_data = bound.to_s
          body = sealing.update(Zlib::Deflate.deflate(JSON.generate(held))) + sealing.final

          "#{VERSION}.#{Base64.urlsafe_encode64(nonce + sealing.auth_tag(TAG) + body, padding: false)}"
        end

        def open(value, bound)
          version, sealed = value.to_s.split(".", 2)

          return nil unless version == VERSION && sealed.present?

          raw = Base64.urlsafe_decode64(sealed)

          return nil if raw.bytesize < NONCE + TAG

          opening = OpenSSL::Cipher.new(CIPHER).decrypt
          opening.key = key
          opening.iv = raw.byteslice(0, NONCE)
          opening.auth_tag = raw.byteslice(NONCE, TAG)
          opening.auth_data = bound.to_s
          packed = opening.update(raw.byteslice((NONCE + TAG)..)) + opening.final
          held = JSON.parse(inflated(packed))

          held.is_a?(Hash) ? held : nil
        rescue ArgumentError, OpenSSL::Cipher::CipherError, Zlib::Error, JSON::ParserError
          nil
        end

        def key
          ::Rails.application.key_generator.generate_key(PURPOSE, 32)
        end

        private

          def inflated(packed)
            inflater = Zlib::Inflate.new
            held = +""

            inflater.inflate(packed) do |chunk|
              held << chunk
              raise Zlib::DataError, "the session cookie unpacks to more than #{UNPACKED} bytes" if held.bytesize > UNPACKED
            end

            inflater.finish
            held
          ensure
            inflater&.close
          end
      end

      def initialize(request, key)
        @request = request
        @key = key
      end

      def read
        bound = session[@key]
        value = pieces.join

        return nil if value.empty?

        held = self.class.open(value, bound) if bound.is_a?(String)

        clear_pieces if held.nil?
        held
      end

      def write(held)
        bound = session[@key]
        bound = session[@key] = SecureRandom.hex(32) unless bound.is_a?(String)
        value = self.class.seal(held, bound)
        written = value.scan(/.{1,#{PIECE}}/o)

        raise Overflow, "this session is #{value.bytesize} bytes, more than #{PIECES} cookies can hold" if written.size > PIECES

        written.each_with_index { |piece, index| jar[name(index)] = options.merge(value: piece) }
        (written.size...PIECES).each { |index| drop(name(index)) }
      end

      def clear
        session.delete(@key)
        clear_pieces
      end

      def name(index)
        base = @request.ssl? ? "__Host-#{@key}" : @key.to_s

        index.zero? ? base : "#{base}-#{index}"
      end

      private

        def session
          @request.session
        end

        def jar
          @request.cookie_jar
        end

        def pieces
          (0...PIECES).map { |index| jar[name(index)] }.take_while(&:present?)
        end

        def clear_pieces
          (0...PIECES).each { |index| drop(name(index)) }
        end

        def drop(named)
          jar.delete(named, path: "/", secure: @request.ssl?, same_site: :lax) if jar.key?(named)
        end

        def options
          lifetime = @request.session_options[:expire_after] if @request.respond_to?(:session_options)

          {
            path: "/", httponly: true, secure: @request.ssl?, same_site: :lax,
            expires: lifetime ? Time.now + lifetime : nil
          }.compact
        end
    end
  end
end
