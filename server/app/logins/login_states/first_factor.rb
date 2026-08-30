module LoginStates
  class FirstFactor < LoginState
    prompts "first-factor" do
      !touched?(:first_factor)
    end

    def start_over!
      expire! :first_factor
    end
  end
end
