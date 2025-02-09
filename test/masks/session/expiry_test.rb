require "test_helper"

require_relative "session_test_case"

module Masks
  class Session
    class ExpiryTest < SessionTestCase
      def structure(session)
        session.structure do
          device

          current :parent, expiry: 1.hour.from_now

          key :test, expiry: Masks::NEVER_EXPIRE
          key :key1, parent: :parent, expiry: Masks::NEVER_EXPIRE
          key :key2

          check :root
          check :check, parent: :test
          check :child, parent: :device
          check :child2, parent: :child
        end

        session[:parent] = "testing123"
      end

      test "session data with no expiry is deleted by the next access" do
        masks_session[:test] = true
        masks_session.test.refresh(nil)

        assert_not masks_session[:test]
      end

      test "session data with default expiry is deleted by the next request" do
        masks_session[:key2] = "test"

        assert_equal "test", masks_session[:key2]

        new_request!

        assert_not masks_session[:key2]
      end

      test "session data expires after a set time" do
        freeze_time

        masks_session[:key1] = true
        masks_session.key1.refresh(1.minute.from_now)

        new_request!

        travel_to 1.minute.from_now
        assert masks_session[:key1]

        travel_to (1.minute + 1.second).from_now
        assert_not masks_session[:key1]
      end

      test "child data expires with the parent" do
        freeze_time

        masks_session[:key1] = "test"

        assert_equal "test", masks_session[:key1]

        travel_to (1.hour + 1.second).from_now

        assert_nil masks_session[:key1]
      end

      test "session data can be set to never expire" do
        freeze_time

        masks_session[:test] = true

        travel_to 1000.years.from_now

        new_request!

        assert masks_session[:test]
      end
    end
  end
end
