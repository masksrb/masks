module Masks
  module Prompts
    class Device
      include Masks::Prompt

      match { device }

      preauth always: true do
        if device.blocked?
          warn! "blocked-device", prompt: "device"
        elsif !device.valid_request?(request)
          session.device.reset!

          warn! "invalid-device", prompt: "device"
        end
      end

      postauth always: true do
        device.save
      end
    end
  end
end
