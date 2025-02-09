require "test_helper"

module Auth
  module Shared
    module Device
      extend ActiveSupport::Concern

      included do
        describe "Devices" do
          test "invalid user agents are blocked" do
            @user_agent = "invalid"

            enter

            assert_prompt "device"
            assert_warning "invalid-device"
            assert_artifacts
          end

          test "devices can be blocked" do
            enter

            Masks::Device.first.block!

            enter

            assert_prompt "device"
            assert_warning "blocked-device"
            assert_artifacts devices: 1
          end

          test "devices are recorded after login" do
            assert_changes -> { Masks::Device.count } do
              log_in "manager"
            end
          end

          test "device expiries are refreshed on access" do
            freeze_time

            log_in "manager"

            expiry = masks_session.device.expires_at

            travel_to 1.year.from_now

            log_in "manager"

            assert expiry < masks_session.device.expires_at
          end

          test "devices are reused" do
            log_in "manager"
            log_in "manager", redirect_uri: "/masks/device"
            log_in "manager", redirect_uri: "/masks/actor"

            assert_equal 1, Masks::Device.count
          end

          test "sessions are reset if user agent changes" do
            iphone_ua!

            assert_login log_in "manager"

            firefox_ua!

            enter

            assert_prompt "device"
            assert_warning "invalid-device"

            enter
            assert_prompt "identify"
          end

          test "sessions are reset if ip address changes" do
            assert_login log_in("manager")

            assert_login

            self.remote_addr = "10.0.0.2"

            enter

            assert_prompt "device"
            assert_warning "invalid-device"

            enter
            assert_prompt "identify"

            assert_login log_in("manager")
          end

          test "sessions are reset if version changes" do
            log_in "manager"

            device = Masks::Device.first

            assert_login

            device.rotate
            device.save!

            enter
            assert_prompt "identify"

            log_in "manager"
            assert_login
          end
        end
      end
    end
  end
end
