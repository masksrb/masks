require "test_helper"

module Auth
  module Shared
    module Error
      extend ActiveSupport::Concern

      included do
        describe "Errors" do
          test "missing-client for attempts with missing clients" do
            key = client.key
            enter
            client.destroy!
            event

            assert_prompt "missing-client"
            assert_settled
          end

          test "expired-state resets automatically on authorization" do
            identify("manager")

            assert_equal entry_json.dig("actor", "identifier"), "manager"

            travel 1.year

            enter

            assert_nil entry_json.dig("actor", "identifier"), "manager"
          end
        end
      end
    end
  end
end
