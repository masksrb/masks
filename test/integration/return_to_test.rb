module Masks
  module Server
    require "test_helper"

    class ReturnToTest < ActionDispatch::IntegrationTest
      setup do
        host! host_for(@tenant)
        @actor = create_actor(@tenant, nickname: "keeper", otp: false)
      end

      def signed_in_from(return_to)
        get "/login", params: { return_to: return_to }
        post "/login", params: { event: "identify", identifier: "keeper" }, as: :json
        post "/login", params: { event: "password", password: "password" }, as: :json

        JSON.parse(response.body)["redirectTo"]
      end

      test "a path on this server is where the sign-in lands" do
        assert_equal "/#export", signed_in_from("/#export")
      end

      test "a query string survives" do
        assert_equal "/?tab=devices", signed_in_from("/?tab=devices")
      end

      test "a client's script address is never handed to the browser to follow" do
        hostile = "javascript://probe.example.com/%0Aalert(document.domain)"
        registration = register
        host! host_for(@tenant)
        within { Client.find_by(client_id: registration["client_id"]).update_columns(redirect_uris: [ hostile ]) }

        sign_in_as(@actor)
        authorize(client_id: registration["client_id"], redirect_uri: hostile)
        post "/login", params: { event: "decline", rid: current_rid }, as: :json

        assert_nil JSON.parse(response.body)["redirectTo"]
      end

      [
        "/\t/evil.example/expired",
        "/\n/evil.example",
        "/\r/evil.example",
        "/ /evil.example",
        "//evil.example",
        "///evil.example",
        "/\\evil.example",
        "https://evil.example/",
        "javascript:alert(1)",
        "evil.example"
      ].each do |hostile|
        test "#{hostile.inspect} is ignored" do
          assert_equal "/", signed_in_from(hostile)
        end
      end
    end
  end
end
