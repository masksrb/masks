module Masks
  module Server
    require "test_helper"

    class ErrorPagesTest < ActionDispatch::IntegrationTest
      DETAILED = "action_dispatch.show_detailed_exceptions".freeze

      setup do
        host! host_for(@tenant)
        @detailed = ::Rails.application.env_config[DETAILED]
        ::Rails.application.env_config[DETAILED] = false
      end

      teardown { ::Rails.application.env_config[DETAILED] = @detailed }

      test "a missing page is the masks not found page" do
        get "/no-such-page", headers: { "Accept" => "*/*" }

        assert_response :not_found
        assert_equal "text/html", response.media_type
        assert_includes response.body, "There is no page at this address."
        assert_includes response.body, "/masks-public/favicon.svg"
      end

      test "a browser that asks for /favicon.ico gets the masks mark" do
        get "/favicon.ico"

        assert_response :success
        assert_equal "image/vnd.microsoft.icon", response.media_type
      end
    end
  end
end
