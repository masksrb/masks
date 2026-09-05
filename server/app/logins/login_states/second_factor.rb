module LoginStates
  class SecondFactor < LoginState
    def enabled?
      actor&.otp?
    end

    prompts "second-factor" do
      login.first_factored? && !login.second_factored?
    end

    def factor!
      login.noted! "mfa" if enabled? && remembered?(DeviceFactor::SECOND_FACTOR)

      super
    end

    def as_json
      { "rememberable" => device.present? }
    end

    def start_over!
      expire! :second_factor
    end
  end
end
