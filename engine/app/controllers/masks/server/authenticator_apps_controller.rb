module Masks
  module Server
    class AuthenticatorAppsController < ApplicationController
      rate_limit to: ::Rails.configuration.masks.account_attempt_limit,
                 within: 3.minutes,
                 by: -> { [ current_tenant.id, current_actor&.id ].join(":") },
                 with: -> { refuse(t("authenticator_apps.too_many_attempts")) },
                 only: :create

      before_action :require_actor
      before_action -> { reauthenticated!("authenticator", t("authenticator_apps.again")) }

      def create
        return refuse(t("authenticator_apps.already")) if current_actor.otp?
        return refuse(t("authenticator_apps.unoffered")) unless AuthenticatorApp.offered?(current_actor)

        secret = AuthenticatorApp.setup_secret(session, current_actor)

        return refuse(t("authenticator_apps.invalid_code")) unless current_actor.adopt_otp!(secret, params[:code].to_s)

        session.delete(AuthenticatorApp::HELD)
        Event.record!(Event::AUTHENTICATOR_ENABLED, actor: current_actor)

        if AuthenticatorApp.backup_codes_offered?(current_actor) && !current_actor.backup_codes?
          codes = current_actor.generate_backup_codes!
          Event.record!(Event::BACKUP_CODES_GENERATED, actor: current_actor, count: codes.length)
          flash[:backup_codes] = codes
        end

        redirect_to root_path(anchor: "authenticator"), notice: t("authenticator_apps.added")
      end

      def destroy
        return refuse(t("authenticator_apps.none")) unless current_actor.otp?

        AuthenticatorApp.remove!(current_actor)
        Event.record!(Event::AUTHENTICATOR_DISABLED, actor: current_actor)

        redirect_to root_path(anchor: "authenticator"), notice: t("authenticator_apps.removed")
      end

      private

        def require_actor
          redirect_to login_path unless current_actor
        end

        def refuse(message)
          redirect_to root_path(anchor: "authenticator"), alert: message
        end
    end
  end
end
