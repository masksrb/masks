class PasswordsController < ApplicationController
  rate_limit to: Rails.configuration.masks.account_attempt_limit,
             within: 3.minutes,
             by: -> { [ current_tenant.id, current_actor&.id ].join(":") },
             with: -> { refuse(t("passwords.too_many_attempts")) }

  before_action :require_actor

  def update
    refusal = Passwords.refusal(replacement, policy)

    return refuse(t("passwords.#{refusal.underscore}", minimum: policy.password_minimum), field: :password) if refusal

    changed = current_actor.change_password!(current, replacement, keeping: current_session)

    return refuse(t("passwords.wrong_current"), field: :current_password) unless changed

    Event.record!(Event::PASSWORD_CHANGED, actor: current_actor)

    redirect_to root_path, notice: t("passwords.changed")
  end

  private

    def require_actor
      redirect_to login_path unless current_actor
    end

    def current
      params.require(:current_password).to_s
    end

    def replacement
      params.require(:password).to_s
    end

    def policy
      @policy ||= SignInPolicy.for(tenant: current_tenant)
    end

    def refuse(message, field: nil)
      return redirect_to root_path, alert: message if field.nil?

      flash[:password_field] = { field.to_s => message }
      redirect_to root_path(anchor: "password")
    end
end
