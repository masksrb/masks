require "test_helper"

require_relative "session_test_case"

module Masks
  class Session
    class CurrentTest < SessionTestCase
      def structure(session)
        session.structure do
          device

          current :key_error
          current :key_quiet, null: true
          current :identifier, track: true, expiry: 1.hour.from_now
        end

        session[:identifier] = "test"
      end

      test "current bags set data under the current key" do
        masks_session.identifier["foo"] = "bar"

        assert_session "bar", [*masks_session.identifier.path, "foo"]
      end

      test "current bags raise KeyErrors without a current record" do
        assert_raises KeyError do
          masks_session.key_error.data
        end
      end

      test "current bags can return null instead of raising without a current record" do
        assert_nil masks_session[:key_quiet]
      end

      test "current bags can track the last current key" do
        masks_session.identifier.current = "manager"
        masks_session.identifier.current = "test"

        assert_equal "test", masks_session.identifier.tracked

        new_request!

        assert_equal "test", masks_session.identifier.tracked
        assert_equal "test", masks_session.identifier.current
      end

      test "current bags that store data are enumerable" do
        ids = %w[manager test test2]

        ids.each do |id|
          masks_session[:identifier] = id
          masks_session.identifier["test"] = true
        end

        assert_equal ids.sort, masks_session.identifier.map(&:current).sort
      end
    end
  end
end
