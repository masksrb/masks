require "test_helper"

module Enries
  class HybridIdTokenTest < AuthTestCase
    shared_tests

    def entry_params
      {
        redirect_uri: "https://example.com",
        response_type: "code id_token",
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
          response_types: ["code id_token"],
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

      assert redirect.dig("fragment", "id_token")
    end
  end
end
