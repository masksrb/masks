class PasswordsController < ApplicationController
  MINIMUM = LoginStates::PasswordReset::MINIMUM_PASSWORD

  rate_limit to: Rails.configuration.masks.account_attempt_limit,
             within: 3.minutes,
             by: -> { [ current_tenant.id, current_actor&.id ].join(":") },
             with: -> { refuse("Too many attempts. Wait a few minutes and try again.") }

  before_action :require_actor

  def update
    return refuse("That password is too short.") if replacement.length < MINIMUM

    changed = current_actor.change_password!(current, replacement, keeping: current_session)

    return refuse("That is not your current password.") unless changed

    redirect_to root_path, notice: "Your password has been changed, and every other session signed out."
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

    def refuse(message)
      redirect_to root_path, alert: message
    end
end
