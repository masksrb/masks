require "test_helper"

class ClientTokenTest < AuthTestCase
  def client
    @client ||=
      Masks::Client.create!(
        key: "testing",
        name: "testing",
        client_type: "confidential",
        redirect_uris: "https://example.com",
      )
  end

  test "client ids are required" do
    post "/token", params: { grant_type: "client_credentials" }

    assert_equal "invalid_request", response.parsed_body["error"]
    assert_includes response.parsed_body["error_description"], "client_id"
  end

  test "support for the 'client_credentials' grant type is required" do
    client =
      Masks::Client.create!(
        name: "public-test",
        client_type: "public",
        redirect_uris: "https://example.com",
      )

    post "/token",
         params: {
           grant_type: "client_credentials",
           client_id: client.key,
           client_secret: client.secret,
         }

    assert_equal "invalid_client", response.parsed_body["error"]
  end

  test "valid client secrets are required" do
    post "/token",
         params: {
           grant_type: "client_credentials",
           client_id: client.key,
         }

    assert_equal "invalid_client", response.parsed_body["error"]

    post "/token",
         params: {
           grant_type: "client_credentials",
           client_id: "invalid",
         }

    assert_equal "invalid_client", response.parsed_body["error"]

    post "/token",
         params: {
           grant_type: "client_credentials",
           client_id: client.key,
           client_secret: client.secret,
         }

    assert_nil response.parsed_body["error"]
  end

  test "client tokens are created" do
    freeze_time

    post "/token",
         params: {
           grant_type: "client_credentials",
           client_id: client.key,
           client_secret: client.secret,
         }

    token =
      assert_token secret: response.parsed_body["access_token"],
                   type: "Masks::ClientToken"

    assert_predicate token, :usable?
    assert_equal "bearer", response.parsed_body["token_type"]
    assert_equal 43_200, response.parsed_body["expires_in"]
  end
end
