module Masks
  module Server
    class DelegationsController < ApplicationController
      before_action :require_actor

      def destroy
        delegation = Delegation.live.includes(:client, connection: :provider).find_by(uuid: params[:id].to_s, actor_id: current_actor.id)

        return redirect_to root_path(anchor: "connections"), alert: t("delegations.unknown") if delegation.nil?

        delegation.revoke!(reason: "stopped by #{current_actor.identifier}", by: current_actor)

        redirect_to root_path(anchor: "connections"),
                    notice: t("delegations.stopped", client: delegation.client.name, provider: delegation.connection.provider.name)
      end

      private

        def require_actor
          redirect_to login_path if current_actor.nil?
        end
    end
  end
end
