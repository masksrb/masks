require_relative "test_helper"

class RegistrationTest < ClientTest
  APP = "https://app.test".freeze

  def setup
    super

    issuer.override("/register", {
      "client_id" => "client-1",
      "client_secret" => "secret-1",
      "client_name" => "things",
      "redirect_uris" => [ "#{APP}/auth/callback" ],
      "registration_access_token" => "registration-token",
      "registration_client_uri" => "#{issuer.url}/register/client-1"
    })
  end

  def create(**attributes)
    Masks::Client::Registration.create(
      issuer.url,
      **{ name: "things", redirect_uris: [ "#{APP}/auth/callback" ] }.merge(attributes)
    )
  end

  def test_open_registration_sends_no_bearer
    create

    assert_nil issuer.last("/register")[:headers]["authorization"]
  end

  def test_an_initial_access_token_is_sent_as_a_bearer
    create(token: "one-time")

    assert_equal "Bearer one-time", issuer.last("/register")[:headers]["authorization"]
  end

  def test_reading_back_uses_the_registration_access_token
    issuer.override("/register/client-1", { "client_id" => "client-1", "client_name" => "things" })

    assert_equal "things", create.read["client_name"]
    assert_equal "Bearer registration-token", issuer.last("/register/client-1")[:headers]["authorization"]
  end

  def test_updating_keeps_the_secret_the_response_does_not_repeat
    registration = create

    issuer.override("/register/client-1", {
      "client_id" => "client-1",
      "client_name" => "things",
      "redirect_uris" => [ "#{APP}/auth/callback", "#{APP}/other" ]
    })

    registration.update(name: "things", redirect_uris: [ "#{APP}/auth/callback", "#{APP}/other" ])

    sent = issuer.last("/register/client-1")

    assert_equal "PUT", sent[:method]
    assert_equal "Bearer registration-token", sent[:headers]["authorization"]
    assert_equal [ "#{APP}/auth/callback", "#{APP}/other" ], registration.metadata["redirect_uris"]
    assert_equal "secret-1", registration.client_secret
  end

  def test_deleting_says_so_with_the_verb_rfc_7592_names
    issuer.override("/register/client-1", {})

    assert create.delete
    assert_equal "DELETE", issuer.last("/register/client-1")[:method]
  end

  def test_a_registration_that_is_refused_raises_rather_than_returning_a_shell
    issuer.override("/register", nil)

    error = assert_raises(Masks::Client::Rejected) { create }

    assert_equal "not_found", error.code
  end
end
