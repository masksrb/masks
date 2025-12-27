module Masks
  class DevicePolicy
    include Policy
    include RequestMatchers

    checks :request do |policy|
      # self is the controller (via context: parameter)
      # policy is the DevicePolicy instance

      device = masks_session.device

      unless device
        stop :device_unknown, status: 429, policy: policy,
          debug: "no device found in session"
      end

      if device.blocked?
        stop :device_blocked, policy: policy,
          debug: "device has been blocked"
      end

      unless device.valid_request?(request)
        stop :device_invalid_request, policy: policy,
          debug: "request fingerprint does not match device"
      end

      if device.new_record? && !device.save
        stop :device_invalid, status: 429, policy: policy,
          debug: "failed to save new device: #{device.errors.full_messages.join(', ')}"
      end

      # Handle captcha if configured
      if captcha_type = policy.config[:captcha]
        captcha = Masks.adapter(captcha_type)
        after = policy.config[:after] || 0
        after = { default: after } unless after.is_a?(Hash)

        method_key = request.get? ? :get : request.request_method.downcase.to_sym
        limit = after[method_key] || after[:default] || 0

        if captcha.passed?(device)
          throttle!(:captcha, reset: true)
        elsif throttled?(:captcha, limit:)
          stop :captcha, policy: policy, assigns: { captcha: captcha },
            debug: "captcha required (#{captcha_type})"
        else
          throttle!(:captcha)
        end
      end
    end

    def captcha_view
      "masks/device_policy/captchas/#{config[:captcha]}"
    end
  end
end
