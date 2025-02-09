require "test_helper"

module Auth
  class CodePublicTest < AuthTestCase
    shared_tests

    def entry_params
      @entry_params ||= {
        redirect_uri: "https://example.com",
        response_type: "code",
        code_challenge: SecureRandom.uuid,
        code_challenge_method: "plain",
        nonce: SecureRandom.uuid,
      }
    end

    def client
      @client ||=
        Masks::Client.create!(
          key: "testing",
          name: "testing",
          client_type: "public",
          redirect_uris: "https://example.com",
        )
    end

    test "unsupported response_types return an error" do
      enter(response_type: "invalid")
      assert_prompt "invalid-response"
      assert_settled
    end

    test "pkce method=S256 is accepted" do
      freeze_time

      enter(response_type: "code", code_challenge_method: "S256")

      assert_prompt "identify"
    end

    test "invalid pkce methods return an error" do
      freeze_time

      enter(response_type: "code", code_challenge_method: "invalid")

      assert_prompt "invalid-pkce"
      assert_settled
    end

    test "authorization codes can be exchanged for access tokens" do
      freeze_time

      log_in "manager"

      secret = assert_redirect_uri.dig("params", "code")

      assert_token secret:, type: "Masks::AuthorizationCode"

      post "/token",
           params: {
             grant_type: "authorization_code",
             client_id: client.key,
             client_secret: client.secret,
             redirect_uri: "https://example.com",
             code_verifier: entry_params[:code_challenge],
             code: secret,
           }

      assert_equal 200, status

      token = response.parsed_body["access_token"]

      assert_token secret: token, type: "Masks::AccessToken"
      assert_equal "bearer", response.parsed_body["token_type"]
      assert_equal 21_600, response.parsed_body["expires_in"]
    end

    test "empty code_challenge redirects back with error" do
      freeze_time

      enter(response_type: "code", code_challenge: "")

      assert_prompt "invalid-pkce"
      assert_settled
    end

    test "pkce is required to exchange codes for access tokens" do
      log_in "manager"

      secret = assert_redirect_uri.dig("params", "code")

      assert_token secret:, type: "Masks::AuthorizationCode"

      post "/token",
           params: {
             grant_type: "authorization_code",
             client_id: client.key,
             client_secret: client.secret,
             redirect_uri: "https://example.com",
             code: secret,
           }

      assert_equal 400, status

      assert_equal "invalid_grant", response.parsed_body["error"]
    end
  end
end
