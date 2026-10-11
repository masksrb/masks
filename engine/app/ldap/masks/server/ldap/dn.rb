module Masks
  module Server
    module Ldap
      class Dn
        class Invalid < StandardError; end

        SPECIAL = [ ",", "+", "\"", "\\", "<", ">", ";", "=" ].freeze
        LONGEST = 1024

        attr_reader :rdns

        class << self
          def parse(text)
            text = text.to_s.dup.force_encoding(Encoding::UTF_8)
            raise Invalid, "a DN is longer than #{LONGEST} bytes" if text.bytesize > LONGEST
            raise Invalid, "a DN is not UTF-8" unless text.valid_encoding?
            return new([]) if text.strip.empty?

            new(split(text, ",").map { |rdn| split(rdn, "+").map { |pair| assertion(pair) }.sort })
          end

          def build(*pairs)
            new(pairs.map { |type, value| [ [ type.to_s.downcase, value.to_s ] ] })
          end

          def escape(value)
            escaped = value.to_s.gsub(/[,+"\\<>;=\x00]/) do |char|
              char == "\x00" ? "\\00" : "\\#{char}"
            end

            escaped = "\\#{escaped}" if escaped.start_with?(" ", "#")
            escaped = "#{escaped[0..-2]}\\ " if escaped.end_with?(" ") && !escaped.end_with?("\\ ")
            escaped
          end

          private

            def split(text, separator)
              parts = []
              current = +""
              index = 0

              while index < text.length
                char = text[index]

                if char == "\\"
                  current << char << text[index + 1].to_s
                  index += 2
                  next
                end

                if char == separator
                  parts << current
                  current = +""
                else
                  current << char
                end

                index += 1
              end

              parts << current
              raise Invalid, "a DN has an empty part" if parts.any? { |part| part.strip.empty? }

              parts
            end

            def assertion(pair)
              type, value = pair.split("=", 2)
              raise Invalid, "#{pair.strip} has no value" if value.nil?

              type = type.strip.downcase
              raise Invalid, "#{type} is not an attribute type" unless type.match?(/\A([a-z][a-z0-9-]*|\d+(\.\d+)*)\z/)

              [ type, unescape(trimmed(value)) ]
            end

            def trimmed(value)
              leading = value.lstrip
              trailing = leading.rstrip
              escaped_space = trailing != leading && trailing[/\\+\z/].to_s.length.odd?

              escaped_space ? "#{trailing} " : trailing
            end

            def unescape(value)
              raise Invalid, "hex-encoded values are not supported" if value.start_with?("#")

              bytes = +"".b
              index = 0

              while index < value.length
                char = value[index]

                if char != "\\"
                  bytes << char.b
                  index += 1
                  next
                end

                following = value[index + 1, 2].to_s

                if following.match?(/\A\h\h\z/)
                  bytes << following.to_i(16).chr
                  index += 3
                elsif following.empty?
                  raise Invalid, "a DN ends inside an escape"
                else
                  bytes << following[0].b
                  index += 2
                end
              end

              decoded = bytes.force_encoding(Encoding::UTF_8)
              raise Invalid, "a DN value is not UTF-8" unless decoded.valid_encoding?

              decoded
            end
        end

        def initialize(rdns)
          @rdns = rdns.freeze
        end

        def root?
          rdns.empty?
        end

        def parent
          Dn.new(rdns.drop(1))
        end

        def child(type, value)
          Dn.new([ [ [ type.to_s.downcase, value.to_s ] ] ] + rdns)
        end

        def depth
          rdns.size
        end

        def first
          rdns.first&.first
        end

        def first_type
          first&.first
        end

        def first_value
          first&.last
        end

        def under?(other)
          return true if other.root?
          return false if other.depth > depth

          normal_rdns.last(other.depth) == other.normal_rdns
        end

        def ==(other)
          other.is_a?(Dn) && normal_rdns == other.normal_rdns
        end
        alias eql? ==

        def hash
          normal_rdns.hash
        end

        def to_s
          rdns.map { |rdn| rdn.map { |type, value| "#{type}=#{Dn.escape(value)}" }.join("+") }.join(",")
        end

        def normal
          normal_rdns.map { |rdn| rdn.map { |type, value| "#{type}=#{Dn.escape(value)}" }.join("+") }.join(",")
        end

        protected

          def normal_rdns
            @normal_rdns ||= rdns.map { |rdn| rdn.map { |type, value| [ type, value.unicode_normalize(:nfkc).downcase ] }.sort }
          end
      end
    end
  end
end
