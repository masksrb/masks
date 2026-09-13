class ConnectionsController < ApplicationController
  before_action :require_actor

  def detach
    connection = Connection.live.find_by(uuid: params[:id], actor_id: current_actor.id)

    return redirect_to root_path, alert: t("connections.unknown") if connection.nil?

    connection.revoke!(reason: "revoked by #{current_actor.identifier}")

    Event.record!(
      Event::CONNECTION_UNLINKED,
      actor: current_actor, provider: connection.provider.key
    )

    redirect_to root_path, notice: t("connections.disconnected", provider: connection.provider.name)
  end

  private

    def require_actor
      redirect_to login_path if current_actor.nil?
    end
end
