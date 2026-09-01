module LoginStates
  class FirstFactor < LoginState
    prompts "first-factor" do
      !login.first_factored?
    end

    def start_over!
      expire! :first_factor
    end
  end
end
