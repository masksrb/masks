require "test_helper"

require_relative "session_test_case"

module Masks
  class Session
    class DeviceTest < SessionTestCase
      def structure(session)
        session.structure do
          device

          key :child, parent: :device
        end
      end

      test "sessions are populated with a device" do
        assert masks_session.current_device
        assert_equal masks_session.device.current, masks_session.current_device
      end

      test "devices are refreshed on access" do
        freeze_time

        og_device = masks_session.current_device.session_key

        travel_to 1.year.from_now
        new_request!

        assert_equal og_device, masks_session.current_device.session_key
      end

      test "a signed cookie is created with the device ID" do
        assert_equal masks_session.device.id,
                     masks_session.rails_request.cookie_jar.signed[
                       "_masks_device"
                     ]
      end

      test "the current device id is stored in the session" do
        assert_session masks_session.device.id, masks_session.device.last_key
      end

      test "child keys are versioned" do
        masks_session[:child] = "testing"

        og_path = masks_session.child.full_path

        assert_session "testing", [*og_path, "value"]

        masks_session[:device].logout!

        new_path = masks_session.child.full_path

        assert_session nil, [*new_path, "value"]

        assert_not_equal og_path, new_path
      end

      test "#id returns the device identifier" do
        assert_equal masks_session.device.id,
                     masks_session.current_device.public_id
      end
    end
  end
end
