require_relative "test_helper"

class EmbeddedTest < ClientTest
  ISSUER = "https://app.example.test/id".freeze

  def setup
    super
    @seen = []
    Masks::Client.embed(method(:serve).to_proc) { |uri| uri.host == "app.example.test" && uri.path.start_with?("/id/") }
  end

  def teardown
    Masks::Client.embed(nil)
    super
  end

  def serve(env)
    @seen << env

    case env["PATH_INFO"]
    when "/id/.well-known/openid-configuration"
      [ 200, { "content-type" => "application/json" }, [ JSON.generate("issuer" => ISSUER, "token_endpoint" => "#{ISSUER}/token") ] ]
    when "/id/token"
      [ 400, { "content-type" => "application/json" }, [ '{"error":"invalid_grant","error_description":"that code is spent"}' ] ]
    when "/id/echo"
      [ 200, { "content-type" => "application/json", "set-cookie" => [ "a=1", "b=2" ] },
        [ JSON.generate("body" => env["rack.input"].read, "type" => env["CONTENT_TYPE"], "auth" => env["HTTP_AUTHORIZATION"]) ] ]
    when "/id/big"
      [ 200, { "content-type" => "application/json" }, [ "a" * 600, "b" * 600 ] ]
    else
      raise "no route for #{env['PATH_INFO']}"
    end
  end

  def test_an_embedded_issuer_answers_discovery_without_a_socket
    discovery = Masks::Client::Issuer.new(ISSUER).discovery

    assert_equal ISSUER, discovery["issuer"]

    env = @seen.last
    assert_equal "app.example.test", env["HTTP_HOST"]
    assert_equal "https", env["rack.url_scheme"]
    assert_equal "127.0.0.1", env["REMOTE_ADDR"]
  end

  def test_the_request_body_and_headers_arrive_as_sent
    answer = Masks::Client::HTTP.post_form("#{ISSUER}/echo", { "code" => "abc" }, { "Authorization" => "Basic eDp5" })

    assert_equal "code=abc", answer["body"]
    assert_equal "application/x-www-form-urlencoded", answer["type"]
    assert_equal "Basic eDp5", answer["auth"]
  end

  def test_a_refusal_comes_back_as_it_does_over_the_network
    error = assert_raises(Masks::Client::Refused) { Masks::Client::HTTP.post_form("#{ISSUER}/token", { "code" => "spent" }) }

    assert_equal "invalid_grant", error.code
    assert_equal 400, error.status
  end

  def test_the_response_is_a_net_http_response_with_every_header
    response = Masks::Client::HTTP.deliver(Net::HTTP::Get.new(URI("#{ISSUER}/echo")))

    assert_kind_of Net::HTTPOK, response
    assert_equal [ "a=1", "b=2" ], response.get_fields("set-cookie")
    assert_equal URI("#{ISSUER}/echo"), response.uri
  end

  def test_the_read_limit_holds
    error = assert_raises(Masks::Client::Error) do
      Masks::Client::HTTP.deliver(Net::HTTP::Get.new(URI("#{ISSUER}/big")), limit: 1000)
    end

    assert_match "more than 1000 bytes", error.message
  end

  def test_an_app_that_raises_is_unreachable
    error = assert_raises(Masks::Client::Unavailable) { Masks::Client::HTTP.get("#{ISSUER}/missing") }

    assert_match "could not be reached", error.message
  end

  def test_each_call_runs_on_a_thread_of_its_own
    callers = []
    Masks::Client.embed(->(_env) { callers << Thread.current; [ 200, {}, [ "{}" ] ] }) { true }

    Masks::Client::HTTP.get("#{ISSUER}/anything")

    refute_same Thread.current, callers.first
  end

  def test_a_url_it_does_not_serve_goes_to_the_network
    Masks::Client::HTTP.get("#{issuer.url}/.well-known/openid-configuration")

    assert_equal 1, issuer.count("/.well-known/openid-configuration")
    assert_empty @seen
  end

  def test_plain_http_is_still_refused_off_loopback
    Masks::Client.embed(method(:serve).to_proc) { true }

    assert_raises(Masks::Client::Insecure) { Masks::Client::HTTP.get("http://app.example.test/id/.well-known/openid-configuration") }
    assert_empty @seen
  end

  def test_embedding_nothing_turns_it_off
    Masks::Client.embed(nil)

    assert_nil Masks::Client.embedded_for(URI("#{ISSUER}/.well-known/openid-configuration"))
  end
end
