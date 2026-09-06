class VerificationsController < ApplicationController
  rate_limit to: Rails.configuration.masks.recovery_limit,
             within: 15.minutes,
             by: -> { [ current_tenant.id, current_actor&.id ].join(":") },
             with: -> { redirect_to root_path, alert: t("verifications.too_many_requests") }

  before_action :require_actor

  def create
    return refuse(t("verifications.no_address")) if current_actor.email.blank?
    return refuse(t("verifications.already_confirmed")) if current_actor.email_verified_at.present?
    return refuse(t("verifications.no_mailer")) unless ActorMailer.deliverable?

    Verifications.open(actor: current_actor)

    redirect_to root_path, notice: t("verifications.sent", email: current_actor.email)
  end

  private

    def require_actor
      redirect_to login_path unless current_actor
    end

    def refuse(message)
      redirect_to root_path, alert: message
    end
end
