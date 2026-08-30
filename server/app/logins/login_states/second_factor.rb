module LoginStates
  class SecondFactor < LoginState
    def enabled?
      actor&.otp?
    end

    prompts "second-factor" do
      touched?(:first_factor) && !touched?(:second_factor)
    end

    def start_over!
      expire! :second_factor
    end
  end
end
