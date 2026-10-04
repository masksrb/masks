module Masks
  module Server
    require "test_helper"

    class OutboundTest < ActiveSupport::TestCase
      setup do
        WebMock.disable!
      end

      teardown do
        WebMock.enable!
        @server&.close
        @thread&.kill
      end

      def serve(body)
        @server = TCPServer.new("127.0.0.1", 0)
        @thread = Thread.new do
          client = @server.accept
          nil while client.gets.to_s.strip.present?
          client.write("HTTP/1.1 200 OK\r\nContent-Length: #{body.bytesize}\r\nConnection: close\r\n\r\n")
          (0...body.bytesize).step(64.kilobytes) { |offset| client.write(body.byteslice(offset, 64.kilobytes)) }
          client.close
        rescue IOError, SystemCallError
          nil
        end

        @server.addr[1]
      end

      test "a request goes to the address that was checked, not to whatever the name resolves to later" do
        port = serve("held")

        uri = URI("http://outbound.invalid:#{port}/")
        response = Outbound.call(uri, Net::HTTP::Get.new(uri), open: Outbound::OPEN_TIMEOUT,
                                                              read: Outbound::READ_TIMEOUT,
                                                              address: IPAddr.new("127.0.0.1"))

        assert_equal "held", Outbound.body(response)
      end

      test "a body larger than the ceiling is abandoned rather than read in full" do
        port = serve("x" * (Outbound::CEILING * 8))

        uri = URI("http://outbound.invalid:#{port}/")
        response = Outbound.call(uri, Net::HTTP::Get.new(uri), open: Outbound::OPEN_TIMEOUT,
                                                              read: Outbound::READ_TIMEOUT,
                                                              address: IPAddr.new("127.0.0.1"))

        assert_equal Outbound::CEILING, response.body.bytesize
      end

      test "a server that drips its headers one byte at a time is abandoned at the deadline" do
        @server = TCPServer.new("127.0.0.1", 0)
        @thread = Thread.new do
          client = @server.accept
          nil while client.gets.to_s.strip.present?
          client.write("HTTP/1.1 200 OK\r\n")
          loop do
            client.write("X")
            sleep 0.2
          end
        rescue IOError, SystemCallError
          nil
        end

        uri = URI("http://outbound.invalid:#{@server.addr[1]}/")
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)

        assert_raises(Outbound::Slow) do
          Outbound.call(uri, Net::HTTP::Get.new(uri), open: 1, read: 1, address: IPAddr.new("127.0.0.1"), within: 1)
        end

        assert_operator Process.clock_gettime(Process::CLOCK_MONOTONIC) - started, :<, 3
      end

      test "addresses that translate to a private IPv4 address are unroutable" do
        assert Outbound.unroutable?(IPAddr.new("64:ff9b::a9fe:a9fe"))
        assert Outbound.unroutable?(IPAddr.new("64:ff9b:1::a00:1"))
        assert Outbound.unroutable?(IPAddr.new("2002:a00:1::1"))
        assert Outbound.unroutable?(IPAddr.new("::a00:1"))
        assert Outbound.unroutable?(IPAddr.new("100::1"))
        assert_not Outbound.unroutable?(IPAddr.new("2606:2800:220:1::1"))
      end

      test "a name with any unroutable address is not vetted" do
        assert_nil Outbound.vetted(URI("http://127.0.0.1/"))
        assert_nil Outbound.vetted(URI("http://169.254.169.254/"))
        assert_nil Outbound.vetted(URI("ftp://example.com/"))
      end

      test "a post is checked against the network even when the caller names no address" do
        deployed do
          resolving("10.1.2.3") do
            error = assert_raises(Outbound::Refused) do
              Outbound.post(URI("https://inside.example.com/hook"), { a: 1 })
            end

            assert_match "will not call", error.message

            assert_raises(Outbound::Refused) { Outbound.post_json(URI("https://inside.example.com/hook"), "{}") }
          end
        end
      end

      test "a range the operator allowed is called, and every other private address is still refused" do
        held = Server.config.outbound_allowed
        Server.config.outbound_allowed = Configuration.outbound_allowed("100.64.0.0/10, 10.20.0.0/16")

        assert_not Outbound.unroutable?(IPAddr.new("100.100.1.2"))
        assert_not Outbound.unroutable?(IPAddr.new("10.20.3.4"))
        assert Outbound.unroutable?(IPAddr.new("10.21.0.1"))
        assert Outbound.unroutable?(IPAddr.new("127.0.0.1"))
        assert_not Outbound.unroutable?(IPAddr.new("93.184.216.34"))
      ensure
        Server.config.outbound_allowed = held
      end

      test "an allowed range that is not one stops the server from booting" do
        error = assert_raises(RuntimeError) { Configuration.outbound_allowed("10.0.0.0/8,tailnet") }

        assert_match "MASKS_OUTBOUND_ALLOWED", error.message
      end
    end
  end
end
