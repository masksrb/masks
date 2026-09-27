module Masks
  module Server
    module LoginStates
      class Password < LoginState
        EXPIRY = 12.hours

        accepts :password

        handles "password", limit: :verifying do
          verify
        end

        def as_json
          { "password" => { "offered" => login.policy.first_factor?(:password) } }
        end

        def verify
          return warn!("missing-identifier") if login.identifier.blank?
          return warn!("factor-not-offered") unless login.policy.first_factor?(:password)
          return warn!("prove-email-first") if login.state("inbox").pending?

          authenticated = Actor.authenticate(login.identifier, update(:password))

          if authenticated
            login.actor = authenticated
            factored! :first_factor, expiry: EXPIRY
            login.first_factored_by! :password
            login.noted! "pwd"
            login.store[RiskCheck::BREACHED] = BreachedPasswords.breached?(update(:password)) if login.policy.refuse_breached_passwords
          else
            refused! "password"
            warn! "invalid-credentials"
          end

          authenticated.present?
        end
      end
    end
  end
end
