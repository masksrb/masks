module Masks
  module Server
    require "test_helper"

    class SessionSwitchTest < ActionDispatch::IntegrationTest
      setup do
        host! host_for(@tenant)

        @first = create_actor(@tenant, nickname: "first", otp: false)
        @second = create_actor(@tenant, nickname: "second")
        enable_otp(@second)
        @registration = register
        host! host_for(@tenant)
      end

      test "signed in to one account, another account's password still leaves its second factor to ask" do
        assert sign_in_as(@first)["settled"]

        authorize(client_id: @registration["client_id"])
        rid = current_rid

        post "/login", params: { event: "identify", identifier: "second", rid: rid }, as: :json
        post "/login", params: { event: "password", password: "password", rid: rid }, as: :json
        body = JSON.parse(response.body)

        assert_equal "second-factor", body["prompt"], body.slice("actor", "prompt", "identifier").inspect
        assert_equal "second", body.dig("actor", "nickname")
      end
    end
  end
end
