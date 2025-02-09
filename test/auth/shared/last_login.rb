require "test_helper"

module Auth
  module Shared
    module LastLogin
      extend ActiveSupport::Concern

      included do
        describe "LastLogin" do
          test "last login timestamp is created" do
            assert_not manager.reload.last_login_at
            log_in "manager"
            assert manager.reload.last_login_at
          end

          test "last login timestamp is updated once on approval" do
            log_in "manager"
            time = manager.reload.last_login_at
            travel 1.second
            event
            event

            assert_equal time, manager.reload.last_login_at
          end
        end
      end
    end
  end
end
