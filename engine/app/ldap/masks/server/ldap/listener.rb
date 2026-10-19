module Masks
  module Server
    module Ldap
      class Listener
        MOST_CONNECTIONS = 256
        IDLE = 5.minutes
        HANDSHAKE = 10.seconds

        EVERY_ADDRESS = "0.0.0.0".freeze
        THIS_MACHINE = "127.0.0.1".freeze

        attr_reader :host, :port

        class << self
          def from_configuration(config = ::Rails.configuration.masks)
            tls = tls(config.ldap_cert, config.ldap_key)

            new(host: host_for(tls: tls, plaintext: config.ldap_plaintext), port: config.ldap_port, tls: tls)
          end

          def host_for(tls:, plaintext:)
            tls || plaintext ? EVERY_ADDRESS : THIS_MACHINE
          end

          def local_only?(config = ::Rails.configuration.masks)
            config.ldap_cert.blank? && !config.ldap_plaintext
          end

          def tls(cert, key)
            return nil if cert.blank? && key.blank?
            raise "MASKS_LDAP_CERT and MASKS_LDAP_KEY are set together or not at all" if cert.blank? || key.blank?

            context = OpenSSL::SSL::SSLContext.new
            chain = File.read(cert).scan(/-----BEGIN CERTIFICATE-----.+?-----END CERTIFICATE-----/m)
            context.cert = OpenSSL::X509::Certificate.new(chain.first)
            context.extra_chain_cert = chain.drop(1).map { |one| OpenSSL::X509::Certificate.new(one) }
            context.key = OpenSSL::PKey.read(File.read(key))
            context.min_version = OpenSSL::SSL::TLS1_2_VERSION
            context
          end
        end

        def initialize(host:, port:, tls: nil, logger: ::Rails.logger, idle: IDLE)
          @host = host
          @wanted_port = port
          @tls = tls
          @logger = logger
          @idle = idle
          @open = Concurrent::AtomicFixnum.new(0)
          @threads = Concurrent::Set.new
        end

        def start
          @server = TCPServer.new(@host, @wanted_port)
          @port = @server.local_address.ip_port
          @logger.info("masks ldap: listening on #{@host}:#{@port}#{' with TLS' if @tls}#{' on this machine only' if @host == THIS_MACHINE}")
          @acceptor = Thread.new { accept_loop }
          self
        end

        def stop
          @server&.close
          @acceptor&.join(1)
          @threads.each(&:kill)
        rescue IOError
          nil
        end

        private

          def accept_loop
            loop do
              socket = @server.accept
              next refuse(socket) if @open.value >= MOST_CONNECTIONS

              @open.increment
              thread = Thread.new(socket) { |held| serve(held) }
              @threads << thread
            end
          rescue IOError, Errno::EBADF
            nil
          end

          def refuse(socket)
            socket.write(Protocol.disconnection(Protocol::BUSY, "too many connections"))
          rescue IOError, SystemCallError
            nil
          ensure
            socket.close
          end

          def serve(socket)
            socket.timeout = @idle
            return unless offered?

            ip_address = socket.remote_address.ip_address
            stream = @tls ? secured(socket) : socket

            Connection.new(stream, ip_address: ip_address, logger: @logger).run if stream
          rescue StandardError => e
            @logger.error("masks ldap: #{e.class}: #{e.message}")
          ensure
            stream&.close unless stream.equal?(socket)
            socket.close unless socket.closed?
            @open.decrement
            @threads.delete(Thread.current)
          end

          def offered?
            ::Rails.application.executor.wrap { Tenant.ldap.exists? }
          end

          def secured(socket)
            stream = OpenSSL::SSL::SSLSocket.new(socket, @tls)
            stream.sync_close = true
            socket.timeout = HANDSHAKE
            stream.accept
            socket.timeout = @idle
            stream
          rescue OpenSSL::SSL::SSLError, IOError, SystemCallError
            nil
          end
      end
    end
  end
end
