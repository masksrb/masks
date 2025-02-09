require "test_helper"

module Auth
  class CodeConfidentialTest < AuthTestCase
    shared_tests

    def entry_params
      { redirect_uri: "https://example.com", response_type: "code" }
    end

    def client
      @client ||=
        Masks::Client.create!(
          key: "testing",
          name: "testing",
          client_type: "confidential",
          redirect_uris: "https://example.com",
          scopes: {
            allowed: ["openid"],
            required: [],
          },
        )
    end

    test "post-login redirect_uri includes an authorization code" do
      log_in "manager"

      redirect = assert_redirect_uri
      secret = redirect.dig("params", "code")
      token = assert_token secret:, type: "Masks::AuthorizationCode"
      assert_predicate token, :usable?
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
             code: secret,
           }

      assert_equal 200, status

      token = response.parsed_body["access_token"]

      assert_token secret: token, type: "Masks::AccessToken"
      assert_equal "bearer", response.parsed_body["token_type"]
      assert_equal 21_600, response.parsed_body["expires_in"]
    end

    test "the openid scope can be used for an id token (in addition to an access token)" do
      log_in "manager", scope: "openid"

      code = assert_redirect_uri.dig("params", "code")

      post "/token",
           params: {
             grant_type: "authorization_code",
             client_id: client.key,
             client_secret: client.secret,
             redirect_uri: "https://example.com",
             code:,
           }

      assert_equal 200, status

      token = response.parsed_body["access_token"]

      assert_token secret: token, type: "Masks::AccessToken"
      assert response.parsed_body["id_token"]
    end

    test "expired/used authorization codes cannot be exchanged for access tokens" do
      freeze_time

      log_in "manager"

      secret = assert_redirect_uri.dig("params", "code")
      code = assert_token secret:, type: "Masks::AuthorizationCode"

      travel_to code.expires_at + 1.second

      post "/token",
           params: {
             grant_type: "authorization_code",
             client_id: client.key,
             client_secret: client.secret,
             redirect_uri: "https://example.com",
             code: secret,
           }

      assert_equal 400, status

      assert_not response.parsed_body["access_token"]
    end

    test "the original redirect_uri must be passed to exchange codes for access tokens" do
      log_in "manager"

      code = assert_redirect_uri.dig("params", "code")

      post "/token",
           params: {
             grant_type: "authorization_code",
             client_id: client.key,
             client_secret: client.secret,
             redirect_uri: "https://example.com/",
             code:,
           }

      assert_equal 400, status

      assert_equal "invalid_grant", response.parsed_body["error"]
    end

    test "access tokens require a valid client id + secret" do
      freeze_time

      log_in "manager"

      code = assert_redirect_uri.dig("params", "code")

      post "/token",
           params: {
             grant_type: "authorization_code",
             client_id: client.key,
             redirect_uri: "https://example.com",
             code:,
           }

      assert_equal 401, status
      assert_equal "invalid_client", response.parsed_body["error"]

      post "/token",
           params: {
             grant_type: "authorization_code",
             client_id: client.key,
             client_secret: "invalid",
             redirect_uri: "https://example.com",
             code:,
           }

      assert_equal 401, status
      assert_equal "invalid_client", response.parsed_body["error"]

      post "/token",
           params: {
             grant_type: "authorization_code",
             client_id: "invalid",
             client_secret: client.secret,
             redirect_uri: "https://example.com",
             code:,
           }

      assert_equal 401, status
      assert_equal "invalid_client", response.parsed_body["error"]
    end
  end
end
