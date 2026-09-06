class ConsentsController < ApplicationController
  before_action :require_actor

  def destroy
    consent = Consent.live.find_by(id: params[:id], actor_id: current_actor.id)

    return redirect_to root_path, alert: t("consents.unknown") if consent.nil?

    consent.revoke!
    RefreshToken.live.where(actor: current_actor, client_id: consent.client_id).find_each(&:revoke!)

    Event.record!(
      Event::CONSENT_REVOKED,
      actor: current_actor, client: consent.client, scopes: Scopes.list(consent.scopes)
    )

    redirect_to root_path, notice: t("consents.revoked", client: consent.client.name)
  end

  private

    def require_actor
      redirect_to login_path unless current_actor
    end
end
