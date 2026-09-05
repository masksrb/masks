module LoginStates
  class OneTimePassword < LoginState
    EXPIRY = 12.hours

    accepts :code, :remember

    def enabled?
      actor&.otp?
    end

    handles "otp" do
      verify
    end

    def verify
      return warn!("missing-first-factor") unless login.first_factored?

      if actor.verify_otp(update(:code))
        factored! :second_factor, expiry: EXPIRY
        remember! DeviceFactor::SECOND_FACTOR if remembering?
        login.noted! "otp", "mfa"
        true
      else
        warn! "invalid-code"
        false
      end
    end

    private

      def remembering?
        device.present? && ActiveModel::Type::Boolean.new.cast(update(:remember))
      end
  end
end
