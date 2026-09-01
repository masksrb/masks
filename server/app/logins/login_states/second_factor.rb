module LoginStates
  class SecondFactor < LoginState
    def enabled?
      actor&.otp?
    end

    prompts "second-factor" do
      login.first_factored? && !login.second_factored?
    end

    def start_over!
      expire! :second_factor
    end
  end
end
