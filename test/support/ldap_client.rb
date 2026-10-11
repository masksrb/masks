module Masks
  module Server
    require "socket"

    class LdapClient
      Ber = Ldap::Ber
      Result = Data.define(:code, :message, :matched)
      Found = Data.define(:dn, :attributes)

      def initialize(port)
        @socket = TCPSocket.new("127.0.0.1", port)
        @socket.timeout = 10
        @next = 0
      end

      def bind(name, password)
        id = send_op(Ber.sequence([ Ber.integer(3), Ber.octets(name), Ber.octets(password, 0x80) ], 0x60))
        result(receive(id))
      end

      def search(base, filter: "(objectClass=*)", scope: 2, attributes: [], size_limit: 0)
        op = Ber.sequence(
          [
            Ber.octets(base), Ber.enumerated(scope), Ber.enumerated(0), Ber.integer(size_limit), Ber.integer(0),
            Ber.boolean(false), encode_filter(filter), Ber.sequence(attributes.map { |name| Ber.octets(name) })
          ],
          0x63
        )
        id = send_op(op)
        found = []

        loop do
          element = receive(id)

          if element.tag == 0x64
            attributes = element.child(1).children.to_h do |attribute|
              [ attribute.child(0).string, attribute.child(1).children.map { |value| value.string.force_encoding("UTF-8") } ]
            end
            found << Found.new(dn: element.child(0).string.force_encoding("UTF-8"), attributes: attributes)
          else
            return [ result(element), found ]
          end
        end
      end

      def raw(op)
        id = send_op(op)
        receive(id)
      end

      def unbind
        send_op(Ber.null(0x42))
      end

      def closed?
        @socket.read(1).nil?
      rescue IOError, SystemCallError
        true
      end

      def close
        @socket.close
      end

      def encode_filter(text)
        encode(Ldap::Filter.parse(text))
      end

      private

        def encode(filter)
          case filter
          when Ldap::Filter::All then Ber.set(filter.filters.map { |part| encode(part) }, 0xa0)
          when Ldap::Filter::Any then Ber.set(filter.filters.map { |part| encode(part) }, 0xa1)
          when Ldap::Filter::Negated then Ber.sequence([ encode(filter.filter) ], 0xa2)
          when Ldap::Filter::Present then Ber.octets(filter.attribute, 0x87)
          when Ldap::Filter::Equal then Ber.sequence([ Ber.octets(filter.attribute), Ber.octets(filter.value) ], 0xa3)
          when Ldap::Filter::Substrings
            parts = []
            parts << Ber.octets(filter.initial, 0x80) if filter.initial
            filter.middle.each { |part| parts << Ber.octets(part, 0x81) }
            parts << Ber.octets(filter.final, 0x82) if filter.final
            Ber.sequence([ Ber.octets(filter.attribute), Ber.sequence(parts) ], 0xa4)
          end
        end

        def send_op(op)
          @next += 1
          @socket.write(Ber.sequence([ Ber.integer(@next), op ]))
          @next
        end

        def receive(id)
          message = Ber.read(@socket, limit: 1_000_000) || raise(IOError, "the server closed the connection")
          raise "expected message #{id}, got #{message.child(0).integer}" unless message.child(0).integer == id

          message.child(1)
        end

        def result(element)
          Result.new(code: element.child(0).integer, matched: element.child(1).string, message: element.child(2).string)
        end
    end
  end
end
