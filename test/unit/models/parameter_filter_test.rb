module Masks
  module Server
    require "test_helper"

    class ParameterFilterTest < ActiveSupport::TestCase
      test "assertions, SAML messages, and request objects never reach the log" do
        filter = ActiveSupport::ParameterFilter.new(::Rails.application.config.filter_parameters)

        held = {
          "client_assertion" => "eyJ.assertion", "assertion" => "eyJ.grant", "SAMLResponse" => "PHNhbWw+",
          "SAMLRequest" => "PHNhbWw+", "RelayState" => "relay", "request" => "eyJ.request",
          "logout_token" => "eyJ.logout", "id_token_hint" => "eyJ.hint"
        }

        assert_equal held.keys.index_with("[FILTERED]"), filter.filter(held)
      end
    end
  end
end
