class VerificationsController < ApplicationController
  rate_limit to: Rails.configuration.masks.recovery_limit,
             within: 15.minutes,
             by: -> { [ current_tenant.id, current_actor&.id ].join(":") },
             with: -> { redirect_to root_path, alert: "Too many requests. Wait a few minutes." }

  before_action :require_actor

  def create
    return refuse("There is no address on this account to confirm.") if current_actor.email.blank?
    return refuse("That address is already confirmed.") if current_actor.email_verified_at.present?
    return refuse("This server cannot send email. Ask an administrator.") unless ActorMailer.deliverable?

    Verifications.open(actor: current_actor)

    redirect_to root_path, notice: "A confirmation link is on its way to #{current_actor.email}."
  end

  private

    def require_actor
      redirect_to login_path unless current_actor
    end

    def refuse(message)
      redirect_to root_path, alert: message
    end
end
