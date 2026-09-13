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

    response = Outbound.get(URI("http://outbound.invalid:#{port}/"), address: IPAddr.new("127.0.0.1"))

    assert_equal "held", Outbound.body(response)
  end

  test "a body larger than the ceiling is abandoned rather than read in full" do
    port = serve("x" * (Outbound::CEILING * 8))

    response = Outbound.get(URI("http://outbound.invalid:#{port}/"), address: IPAddr.new("127.0.0.1"))

    assert_equal Outbound::CEILING, response.body.bytesize
  end

  test "a name with any unroutable address is not vetted" do
    assert_nil Outbound.vetted(URI("http://127.0.0.1/"))
    assert_nil Outbound.vetted(URI("http://169.254.169.254/"))
    assert_nil Outbound.vetted(URI("ftp://example.com/"))
  end
end
