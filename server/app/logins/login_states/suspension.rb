module LoginStates
  class Suspension < LoginState
    def enabled?
      actor.present? && login.first_factored?
    end

    def factor!
      return unless enabled? && actor.suspended?

      refused!("suspended")
      refuse!("access_denied", "this account is suspended")
    end
  end
end
