require_relative "test_helper"

class HttpTest < ClientTest
  def teardown
    Masks::Client.plain_http = nil
    super
  end

  def checked(url)
    Masks::Client::HTTP.checked(URI.parse(url))
  end

  def test_plain_http_is_refused_off_loopback_before_anything_is_sent
    error = assert_raises(Masks::Client::Insecure) { Masks::Client::HTTP.get("http://auth.example.com/.well-known/openid-configuration") }

    assert_match "http://auth.example.com", error.message
    assert_raises(Masks::Client::Insecure) { Masks::Client::Issuer.new("http://auth.example.com").discovery }
    assert_raises(Masks::Client::Insecure) { checked("http://127.0.0.1.example.com/") }
    assert_raises(Masks::Client::Insecure) { checked("http://10.0.0.5/") }
  end

  def test_https_and_loopback_hosts_are_allowed
    [ "https://auth.example.com/", "http://localhost:3000/", "http://masks.localhost:12345/",
      "http://127.0.0.1:9/", "http://[::1]:9/" ].each { |url| assert checked(url) }
  end

  def test_plain_http_is_allowed_when_switched_on
    Masks::Client.plain_http = true

    assert checked("http://masks:3000/")
  end

  def test_only_http_and_https_are_spoken
    assert_raises(Masks::Client::Error) { checked("ftp://auth.example.com/") }
    assert_raises(Masks::Client::Error) { checked("file:///etc/passwd") }
  end

  def test_a_response_over_a_megabyte_is_refused
    issuer.override("/big", { "padding" => "a" * (1 << 20) })

    error = assert_raises(Masks::Client::Error) { Masks::Client::HTTP.get("#{issuer.url}/big") }

    assert_match "more than", error.message
  end

  def test_a_fetch_over_eight_megabytes_is_refused
    issuer.override("/photo", { "padding" => "a" * (8 << 20) })

    error = assert_raises(Masks::Client::Error) { Masks::Client::HTTP.fetch("#{issuer.url}/photo") }

    assert_match "more than", error.message
  end

  def test_a_fetch_under_its_limit_answers_with_the_whole_response
    issuer.override("/photo", { "padding" => "a" * (2 << 20) })

    answer = Masks::Client::HTTP.fetch("#{issuer.url}/photo")

    assert_kind_of Net::HTTPSuccess, answer
    assert_operator answer.body.bytesize, :>, 2 << 20
  end

  def test_a_json_answer_that_is_not_an_object_is_refused
    issuer.override("/list", [ 200, [ "a", "b" ] ])

    error = assert_raises(Masks::Client::Refused) { Masks::Client::HTTP.get("#{issuer.url}/list") }

    assert_equal "server_error", error.code
    assert_match "not an object", error.message
  end

  def test_a_refusal_with_a_body_that_is_not_an_object_still_names_its_status
    issuer.override("/broken", [ 502, [ "a" ] ])

    error = assert_raises(Masks::Client::Refused) { Masks::Client::HTTP.get("#{issuer.url}/broken") }

    assert_equal "server_error", error.code
  end

  def test_an_empty_answer_is_an_empty_object
    issuer.override("/empty", [ 200, {} ])

    assert_equal({}, Masks::Client::HTTP.get("#{issuer.url}/empty"))
  end
end
