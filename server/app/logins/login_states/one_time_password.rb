module LoginStates
  class OneTimePassword < LoginState
    EXPIRY = 12.hours

    accepts :code

    def enabled?
      actor&.otp?
    end

    handles "otp" do
      verify
    end

    def verify
      return warn!("missing-first-factor") unless touched?(:first_factor)

      if actor.verify_otp(update(:code))
        factored! :second_factor, expiry: EXPIRY
        true
      else
        warn! "invalid-code"
        false
      end
    end
  end
end
