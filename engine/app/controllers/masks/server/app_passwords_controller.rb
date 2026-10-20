module Masks
  module Server
    class AppPasswordsController < ApplicationController
      ANCHOR = "app-passwords".freeze

      before_action :require_actor

      def create
        return unless reauthenticated!(ANCHOR, t("app_passwords.again"))

        client = Client.active.find_by(client_id: params[:client_id].to_s)
        held = AppPassword.issue!(actor: current_actor, client: client, name: params[:name])

        Event.record!(Event::APP_PASSWORD_CREATED, actor: current_actor, client: client, name: held.name)

        flash[:app_password] = { "name" => held.name, "app" => client.name, "secret" => held.secret }
        redirect_to root_path(anchor: ANCHOR)
      rescue AppPassword::Refused => e
        redirect_to root_path(anchor: ANCHOR), alert: t("app_passwords.refused.#{e.message}", most: AppPassword::MOST)
      end

      def destroy
        held = AppPassword.live.find_by(id: params[:id].to_s[/\A\d+\z/], actor: current_actor)

        return redirect_to root_path(anchor: ANCHOR), alert: t("app_passwords.unknown") if held.nil?

        held.revoke!

        Event.record!(Event::APP_PASSWORD_REVOKED, actor: current_actor, client: held.client, name: held.name)

        redirect_to root_path(anchor: ANCHOR), notice: t("app_passwords.revoked", name: held.name)
      end

      private

        def require_actor
          redirect_to login_path unless current_actor
        end
    end
  end
end
