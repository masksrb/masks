module Masks
  module Server
    module Ldap
      module Protocol
        class Invalid < StandardError; end

        BIND_REQUEST = 0x60
        BIND_RESPONSE = 0x61
        UNBIND_REQUEST = 0x42
        SEARCH_REQUEST = 0x63
        SEARCH_RESULT_ENTRY = 0x64
        SEARCH_RESULT_DONE = 0x65
        MODIFY_REQUEST = 0x66
        ADD_REQUEST = 0x68
        DELETE_REQUEST = 0x4a
        MODIFY_DN_REQUEST = 0x6c
        COMPARE_REQUEST = 0x6e
        ABANDON_REQUEST = 0x50
        EXTENDED_REQUEST = 0x77
        EXTENDED_RESPONSE = 0x78

        SIMPLE = 0x80
        CONTROLS = 0xa0
        RESPONSE_NAME = 0x8a

        ANSWERS = {
          MODIFY_REQUEST => 0x67,
          ADD_REQUEST => 0x69,
          DELETE_REQUEST => 0x6b,
          MODIFY_DN_REQUEST => 0x6d,
          COMPARE_REQUEST => 0x6f,
          EXTENDED_REQUEST => EXTENDED_RESPONSE
        }.freeze

        DISCONNECTION = "1.3.6.1.4.1.1466.20036".freeze
        WHO_AM_I = "1.3.6.1.4.1.4203.1.11.3".freeze
        REQUEST_NAME = 0x80
        RESPONSE_VALUE = 0x8b

        SUCCESS = 0
        OPERATIONS_ERROR = 1
        PROTOCOL_ERROR = 2
        SIZE_LIMIT_EXCEEDED = 4
        AUTH_METHOD_NOT_SUPPORTED = 7
        NO_SUCH_OBJECT = 32
        INVALID_DN_SYNTAX = 34
        INVALID_CREDENTIALS = 49
        INSUFFICIENT_ACCESS_RIGHTS = 50
        BUSY = 51
        UNAVAILABLE = 52
        UNWILLING_TO_PERFORM = 53
        OTHER = 80

        Message = Data.define(:id, :operation)
        Bind = Data.define(:version, :name, :password, :simple)
        Search = Data.define(:base, :scope, :size_limit, :types_only, :filter, :attributes)
        Unbind = Data.define
        Abandon = Data.define
        WhoAmI = Data.define
        Unsupported = Data.define(:tag)

        module_function

        def message(element)
          raise Invalid, "a message is a sequence" unless element.tag == Ber::SEQUENCE

          id = element.child(0, Ber::INTEGER).integer
          raise Invalid, "message ID #{id} is out of range" unless (0..(2**31 - 1)).cover?(id)

          Message.new(id: id, operation: operation(element.child(1)))
        rescue Ber::Error, Filter::Invalid => e
          raise Invalid, e.message
        end

        def operation(element)
          case element.tag
          when BIND_REQUEST then bind(element)
          when SEARCH_REQUEST then search(element)
          when UNBIND_REQUEST then Unbind.new
          when ABANDON_REQUEST then Abandon.new
          when EXTENDED_REQUEST then extended(element)
          else Unsupported.new(tag: element.tag)
          end
        end

        def extended(element)
          name = element.children.find { |part| part.tag == REQUEST_NAME }&.string

          name == WHO_AM_I ? WhoAmI.new : Unsupported.new(tag: EXTENDED_REQUEST)
        end

        def who_am_i(id, identity)
          envelope(id, result(EXTENDED_RESPONSE, SUCCESS, extra: [ Ber.octets(identity, RESPONSE_VALUE) ]))
        end

        def bind(element)
          authentication = element.child(2)

          Bind.new(
            version: element.child(0, Ber::INTEGER).integer,
            name: text(element.child(1, Ber::OCTET_STRING).string),
            password: authentication.tag == SIMPLE ? authentication.string.dup.force_encoding(Encoding::UTF_8) : nil,
            simple: authentication.tag == SIMPLE
          )
        end

        def search(element)
          scope = element.child(1, Ber::ENUMERATED).integer
          raise Invalid, "scope #{scope} is not base, one, or subtree" unless Directory::SCOPES.include?(scope)

          Search.new(
            base: text(element.child(0, Ber::OCTET_STRING).string),
            scope: scope,
            size_limit: element.child(3, Ber::INTEGER).integer,
            types_only: element.child(5, Ber::BOOLEAN).boolean,
            filter: Filter.from(element.child(6)),
            attributes: element.child(7, Ber::SEQUENCE).children.map { |attribute| text(attribute.string) }
          )
        end

        def text(bytes)
          decoded = bytes.dup.force_encoding(Encoding::UTF_8)
          raise Invalid, "a string is not UTF-8" unless decoded.valid_encoding?

          decoded
        end

        def result(tag, code, message: "", matched: "", extra: [])
          Ber.sequence(
            [ Ber.enumerated(code), Ber.octets(matched.to_s), Ber.octets(message.to_s), *extra ],
            tag
          )
        end

        def envelope(id, operation)
          Ber.sequence([ Ber.integer(id), operation ])
        end

        def bind_response(id, code, message = "")
          envelope(id, result(BIND_RESPONSE, code, message: message))
        end

        def search_done(id, code, message = "", matched: "")
          envelope(id, result(SEARCH_RESULT_DONE, code, message: message, matched: matched))
        end

        def search_entry(id, dn, attributes, types_only: false)
          envelope(
            id,
            Ber.sequence(
              [
                Ber.octets(dn.to_s),
                Ber.sequence(
                  attributes.map do |name, values|
                    Ber.sequence([ Ber.octets(name), Ber.set(types_only ? [] : values.map { |value| Ber.octets(value) }) ])
                  end
                )
              ],
              SEARCH_RESULT_ENTRY
            )
          )
        end

        def refusal(id, tag, message)
          envelope(id, result(ANSWERS.fetch(tag), UNWILLING_TO_PERFORM, message: message))
        end

        def disconnection(code, message)
          envelope(0, result(EXTENDED_RESPONSE, code, message: message, extra: [ Ber.octets(DISCONNECTION, RESPONSE_NAME) ]))
        end
      end
    end
  end
end
