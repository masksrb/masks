module Masks
  module Server
    module Pictures
      class Unreadable < StandardError; end

      CONTENT_TYPE = "image/webp".freeze
      QUALITY = 82
      PIXELS = 100_000_000

      MAGIC = {
        "\x89PNG\r\n\x1a\n".b => "image/png",
        "\xFF\xD8\xFF".b => "image/jpeg",
        "GIF87a".b => "image/gif",
        "GIF89a".b => "image/gif"
      }.freeze

      RIFF = "RIFF".b
      WEBP = "WEBP".b

      class << self
        def digest(bytes)
          Digest::SHA256.hexdigest(bytes)[0, 16]
        end

        def sniff(bytes)
          head = bytes.to_s.b

          return "image/webp" if head.start_with?(RIFF) && head[8, 4] == WEBP

          MAGIC.find { |magic, _| head.start_with?(magic) }&.last
        end

        def square(bytes, size)
          refuse_a_bomb(bytes)
          thumbnail(bytes, size)
        rescue Vips::Error => e
          raise Unreadable, e.message
        end

        def resized(data, digest, size, stored:, kind:)
          return data if size.nil? || size >= stored

          ::Rails.cache.fetch([ kind, digest, size ], expires_in: 1.day) { thumbnail(data, size) }
        end

        private

          def images
            require "vips"

            Vips::Image
          end

          def thumbnail(bytes, size)
            images.thumbnail_buffer(bytes, size, height: size, size: :both, crop: :attention)
                  .webpsave_buffer(Q: QUALITY, strip: true)
          end

          def refuse_a_bomb(bytes)
            header = images.new_from_buffer(bytes, "", access: :sequential)

            return if header.width.to_i * header.height.to_i <= PIXELS

            raise Unreadable, "that image has too many pixels to resize"
          end
      end
    end
  end
end
