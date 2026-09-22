module Masks
  module Server
    class AppsController < ApplicationController
      before_action :require_actor

      def destroy
        client = Client.find_by(client_id: params[:client_id])

        return redirect_to root_path, alert: t("apps.unknown") if client.nil?

        consent = Consent.live.find_by(actor: current_actor, client: client)
        scopes = Apps.held_by(current_actor).find { |app| app.client.id == client.id }&.scope_list

        consent&.revoke!

        Delegation.live.where(actor: current_actor, client: client).find_each do |delegation|
          delegation.revoke!(reason: "access for #{client.name} revoked by #{current_actor.identifier}", by: current_actor)
        end

        Token.live.where(actor: current_actor, client: client).find_each(&:revoke!)

        Event.record!(
          Event::CONSENT_REVOKED,
          actor: current_actor, client: client, scopes: scopes || []
        )

        redirect_to root_path, notice: t("apps.revoked", client: client.name)
      end

      private

        def require_actor
          redirect_to login_path unless current_actor
        end
    end
  end
end
