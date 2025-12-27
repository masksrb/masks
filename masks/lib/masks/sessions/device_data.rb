module Masks
  module Sessions
    module DeviceData
      extend ActiveSupport::Concern

      DEVICE_KEY = 'masks.device'

      def device_id
        @device_id ||= begin
          cookie_value = request.cookie_jar.signed[Masks.mode.device_cookie]&.presence
          session_value = data.fetch(DEVICE_KEY, nil)&.presence
          session_value || cookie_value || SecureRandom.alphanumeric(32)
        end
      end

      def device
        request.env[DEVICE_KEY] ||= refresh_device(Masks.devices.identify(device_id, request:))
      end

      private

      def refresh_device(device)
        request.cookie_jar.signed[Masks.mode.device_cookie] = {
          value: device.public_id,
          expires: Masks.time.expires_at(:device_cookie_lifetime),
        }

        data[DEVICE_KEY] = device.public_id

        device
      end
    end
  end
end
