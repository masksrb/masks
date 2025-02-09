require "test_helper"

module Auth
  class HybridTokenTest < AuthTestCase
    shared_tests

    def entry_params
      {
        redirect_uri: "https://example.com",
        response_type: "code token",
        nonce: SecureRandom.uuid,
      }
    end

    def client
      @client ||=
        Masks::Client.create!(
          key: "testing",
          name: "testing",
          client_type: "confidential",
          redirect_uris: "https://example.com",
          response_types: ["code token"],
        )
    end

    test "nonces are required" do
      enter(nonce: "")

      assert_prompt "missing-nonce"
      assert_settled
    end

    test "unsupported response_types return an error" do
      enter(response_type: "code")
      assert_prompt "invalid-response"
      assert_settled
    end

    test "id_tokens are returned in the uri" do
      freeze_time

      log_in "manager"

      redirect = assert_redirect_uri
      secret = redirect.dig("fragment", "access_token")

      assert_token secret:, type: "Masks::AccessToken"
    end
  end
end
