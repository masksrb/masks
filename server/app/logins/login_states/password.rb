module LoginStates
  class Password < LoginState
    EXPIRY = 12.hours

    accepts :password

    handles "password", limit: :verifying do
      verify
    end

    def verify
      return warn!("missing-identifier") if login.identifier.blank?
      return warn!("factor-not-offered") unless login.policy.first_factor?(:password)

      authenticated = Actor.authenticate(login.identifier, update(:password))

      if authenticated
        login.actor = authenticated
        factored! :first_factor, expiry: EXPIRY
        login.noted! "pwd"
      else
        refused! "password"
        warn! "invalid-credentials"
      end

      authenticated.present?
    end
  end
end
