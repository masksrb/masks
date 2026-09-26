module Masks
  module Server
    module LoginStates
      class OneTimePassword < LoginState
        accepts :code, :remember

        def enabled?
          actor&.otp?
        end

        handles "otp", limit: :verifying do
          verify
        end

        def verify
          return warn!("missing-first-factor") unless login.first_factored?

          if actor.verify_otp(update(:code))
            second_factored! "otp"
            true
          else
            refused! "otp"
            warn! "invalid-code"
            false
          end
        end
      end
    end
  end
end
