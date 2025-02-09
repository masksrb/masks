module Masks
  module Prompts
    class Device
      include Masks::Prompt

      match { current_device }

      preauth always: true do
        if current_device.blocked?
          warn! "blocked-device", prompt: "device"
        elsif !current_device.valid_request?(request)
          session.device.reset!

          warn! "invalid-device", prompt: "device"
        end
      end

      postauth always: true do
        current_device.save
      end
    end
  end
end
