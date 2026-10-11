module Masks
  module Server
    module Ldap
      class Connection
        LARGEST_MESSAGE = 64.kilobytes
        MOST_ENTRIES = 10_000
        AGENT = "LDAP".freeze

        def initialize(socket, ip_address:, logger: ::Rails.logger)
          @socket = socket
          @ip_address = ip_address
          @logger = logger
          @bound = nil
        end

        def run
          loop do
            element = Ber.read(@socket, limit: LARGEST_MESSAGE)
            break if element.nil?

            break if answer(Protocol.message(element)) == :close
          end
        rescue Protocol::Invalid, Ber::Error => e
          @logger.info("masks ldap: #{@ip_address} sent something unreadable: #{e.message}")
          write(Protocol.disconnection(Protocol::PROTOCOL_ERROR, e.message))
        rescue IOError, SystemCallError, OpenSSL::SSL::SSLError
          nil
        end

        private

          def answer(message)
            case message.operation
            when Protocol::Unbind then :close
            when Protocol::Abandon then nil
            when Protocol::Bind then within { bind(message) }
            when Protocol::Search then within { search(message) }
            when Protocol::WhoAmI then write(Protocol.who_am_i(message.id, @bound ? "dn:#{@bound.dn}" : ""))
            when Protocol::Unsupported then unsupported(message)
            end
          end

          def within(&block)
            ::Rails.application.executor.wrap do
              Current.set(ip_address: @ip_address, user_agent: AGENT, &block)
            end
          end

          def unsupported(message)
            unless Protocol::ANSWERS.key?(message.operation.tag)
              write(Protocol.disconnection(Protocol::PROTOCOL_ERROR, "unknown operation"))
              return :close
            end

            write(Protocol.refusal(message.id, message.operation.tag, "this directory is read-only"))
            nil
          end

          def bind(message)
            request = message.operation
            @bound = nil

            if request.version != 3
              return write(Protocol.bind_response(message.id, Protocol::PROTOCOL_ERROR, "only LDAPv3 is spoken here"))
            end

            unless request.simple
              return write(Protocol.bind_response(message.id, Protocol::AUTH_METHOD_NOT_SUPPORTED, "only simple binds are supported"))
            end

            outcome = Gate.new(ip_address: @ip_address).bind(request.name, request.password)
            @bound = outcome.bound

            write(Protocol.bind_response(message.id, outcome.code, outcome.message))
          end

          def search(message)
            request = message.operation

            return root(message) if request.base.empty? && request.scope == Directory::BASE

            unless @bound&.service?
              return write(Protocol.search_done(message.id, Protocol::INSUFFICIENT_ACCESS_RIGHTS, "bind with an LDAP credential to search"))
            end

            Tenant.switch(@bound.tenant) { search_within(message, request) }
          end

          def search_within(message, request)
            unless LdapCredential.live.exists?(id: @bound.subject)
              @bound = nil
              return write(Protocol.search_done(message.id, Protocol::INSUFFICIENT_ACCESS_RIGHTS, "the LDAP credential was revoked"))
            end

            directory = Directory.new(@bound.tenant)
            base = Dn.parse(request.base)
            entries = directory.search(base, request.scope, uid: Filter.pinned(request.filter, "uid"))
            limit = [ request.size_limit, MOST_ENTRIES ].select(&:positive?).min
            sent = 0

            entries.each do |entry|
              next unless request.filter.match(entry) == true

              if sent >= limit
                return write(Protocol.search_done(message.id, Protocol::SIZE_LIMIT_EXCEEDED, "more than #{limit} entries match"))
              end

              write(Protocol.search_entry(message.id, entry.dn, entry.selected(request.attributes), types_only: request.types_only))
              sent += 1
            end

            write(Protocol.search_done(message.id, Protocol::SUCCESS))
          rescue Dn::Invalid => e
            write(Protocol.search_done(message.id, Protocol::INVALID_DN_SYNTAX, e.message))
          rescue Directory::NoSuchObject => e
            write(Protocol.search_done(message.id, Protocol::NO_SUCH_OBJECT, "no such entry", matched: e.matched.to_s))
          end

          def root(message)
            request = message.operation
            attributes = {
              "objectClass" => %w[top extensibleObject],
              "supportedLDAPVersion" => [ "3" ],
              "vendorName" => [ "masks" ],
              "vendorVersion" => [ Masks::Server::VERSION ],
              "namingContexts" => @bound ? [ Directory.base_for(@bound.tenant).to_s ] : []
            }
            entry = Entry.new(Dn.new([]), attributes)

            if request.filter.match(entry) == true
              write(Protocol.search_entry(message.id, "", entry.selected(request.attributes), types_only: request.types_only))
            end

            write(Protocol.search_done(message.id, Protocol::SUCCESS))
          end

          def write(bytes)
            @socket.write(bytes)
            nil
          end
      end
    end
  end
end
