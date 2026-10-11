module Masks
  module Server
    module Ldap
      module Ber
        class Error < StandardError; end

        BOOLEAN = 0x01
        INTEGER = 0x02
        OCTET_STRING = 0x04
        NULL = 0x05
        ENUMERATED = 0x0a
        SEQUENCE = 0x30
        SET = 0x31

        CONSTRUCTED = 0x20
        DEEPEST = 32

        Element = Data.define(:tag, :value) do
          def constructed?
            tag.anybits?(CONSTRUCTED)
          end

          def children
            raise Error, "element #{format('%#04x', tag)} is primitive" unless constructed?

            value
          end

          def string
            raise Error, "element #{format('%#04x', tag)} is constructed" if constructed?

            value
          end

          def integer
            Ber.integer_from(string)
          end

          def boolean
            string.bytes.any?(&:nonzero?)
          end

          def child(index, tag = nil)
            found = children[index] || raise(Error, "element #{format('%#04x', self.tag)} has no part #{index}")
            raise Error, "expected #{format('%#04x', tag)}, got #{format('%#04x', found.tag)}" if tag && found.tag != tag

            found
          end
        end

        module_function

        def read(io, limit:)
          first = io.read(1)
          return nil if first.nil?

          tag = first.ord
          raise Error, "high tag numbers are not supported" if tag & 0x1f == 0x1f

          head = io.read(1) || raise(Error, "the stream ended inside a length")
          size = head.ord
          header = first + head

          if size.anybits?(0x80)
            count = size & 0x7f
            raise Error, "indefinite and oversized lengths are not supported" if count.zero? || count > 4

            more = io.read(count)
            raise Error, "the stream ended inside a length" if more.nil? || more.bytesize < count

            header += more
            size = more.bytes.inject(0) { |sum, byte| (sum << 8) | byte }
          end

          raise Error, "a message of #{size} bytes is larger than #{limit}" if size > limit

          body = size.zero? ? "".b : io.read(size)
          raise Error, "the stream ended inside a message" if body.nil? || body.bytesize < size

          decode(header + body)
        end

        def decode(bytes)
          bytes = bytes.b
          element, finish = element_at(bytes, 0, 0)
          raise Error, "#{bytes.bytesize - finish} bytes follow the element" if finish != bytes.bytesize

          element
        end

        def element_at(bytes, start, depth)
          raise Error, "elements nest deeper than #{DEEPEST}" if depth > DEEPEST
          raise Error, "the input ended before a tag" if start >= bytes.bytesize

          tag = bytes.getbyte(start)
          raise Error, "high tag numbers are not supported" if tag & 0x1f == 0x1f

          size, offset = length_at(bytes, start + 1)
          finish = offset + size
          raise Error, "an element runs past the end of the input" if finish > bytes.bytesize

          content = bytes.byteslice(offset, size)

          value = if tag.anybits?(CONSTRUCTED)
            parts_of(content, depth + 1)
          else
            content
          end

          [ Element.new(tag: tag, value: value), finish ]
        end

        def parts_of(content, depth)
          found = []
          position = 0

          while position < content.bytesize
            element, position = element_at(content, position, depth)
            found << element
          end

          found
        end

        def length_at(bytes, position)
          first = bytes.getbyte(position) || raise(Error, "the input ended before a length")
          return [ first, position + 1 ] if first < 0x80

          count = first & 0x7f
          raise Error, "indefinite and oversized lengths are not supported" if count.zero? || count > 4
          raise Error, "the input ended inside a length" if position + count >= bytes.bytesize

          size = 0
          count.times { |index| size = (size << 8) | bytes.getbyte(position + 1 + index) }

          [ size, position + 1 + count ]
        end

        def integer_from(bytes)
          raise Error, "an integer has no content" if bytes.empty?
          raise Error, "an integer is longer than eight bytes" if bytes.bytesize > 8

          number = bytes.bytes.inject(0) { |sum, byte| (sum << 8) | byte }
          bytes.getbyte(0) >= 0x80 ? number - (1 << (8 * bytes.bytesize)) : number
        end

        def length(size)
          return size.chr.b if size < 0x80

          bytes = []
          while size.positive?
            bytes.unshift(size & 0xff)
            size >>= 8
          end

          [ 0x80 | bytes.size, *bytes ].pack("C*")
        end

        def tlv(tag, content)
          content = content.b
          tag.chr.b + length(content.bytesize) + content
        end

        def integer(number, tag = INTEGER)
          bytes = []

          loop do
            bytes.unshift(number & 0xff)
            number >>= 8
            break if (number.zero? && bytes.first < 0x80) || (number == -1 && bytes.first >= 0x80)
          end

          tlv(tag, bytes.pack("C*"))
        end

        def enumerated(number, tag = ENUMERATED)
          integer(number, tag)
        end

        def boolean(value, tag = BOOLEAN)
          tlv(tag, value ? "\xff".b : "\x00".b)
        end

        def octets(value, tag = OCTET_STRING)
          tlv(tag, value.to_s.dup.force_encoding(Encoding::BINARY))
        end

        def null(tag = NULL)
          tlv(tag, "")
        end

        def sequence(parts, tag = SEQUENCE)
          tlv(tag, parts.join.b)
        end

        def set(parts, tag = SET)
          sequence(parts, tag)
        end
      end
    end
  end
end
