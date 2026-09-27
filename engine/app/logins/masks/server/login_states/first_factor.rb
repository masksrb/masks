module Masks
  module Server
    module LoginStates
      class FirstFactor < LoginState
        prompts "first-factor" do
          !login.first_factored?
        end

        def as_json
          { "passwordOffered" => login.policy.first_factor?(:password) }
        end

        def start_over!
          expire! :first_factor
        end
      end
    end
  end
end
