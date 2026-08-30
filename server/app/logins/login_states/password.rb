module LoginStates
  class Password < LoginState
    EXPIRY = 12.hours

    accepts :password

    handles "password" do
      verify
    end

    def verify
      return warn!("missing-identifier") if login.identifier.blank?

      authenticated = Actor.authenticate(login.identifier, update(:password))

      if authenticated
        login.actor = authenticated
        factored! :first_factor, expiry: EXPIRY
      else
        warn! "invalid-credentials"
      end

      authenticated.present?
    end
  end
end
