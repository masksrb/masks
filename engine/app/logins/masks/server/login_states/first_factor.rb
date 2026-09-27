module Masks
  module Server
    module LoginStates
      class FirstFactor < LoginState
        prompts "first-factor" do
          warn! "organization-sign-in" if login.organization_unsatisfied?

          !login.first_factored?
        end

        def start_over!
          expire! :first_factor
        end
      end
    end
  end
end
