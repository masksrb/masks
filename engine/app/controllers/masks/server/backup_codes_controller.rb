module Masks
  module Server
    class BackupCodesController < ApplicationController
      before_action :require_actor
      before_action -> { reauthenticated!("backup-codes", t("backup_codes.again")) }

      def create
        return refuse(t("backup_codes.unoffered")) unless AuthenticatorApp.backup_codes_offered?(current_actor)
        return refuse(t("backup_codes.no_second_factor")) unless current_actor.second_factor?

        codes = current_actor.generate_backup_codes!
        Event.record!(Event::BACKUP_CODES_GENERATED, actor: current_actor, count: codes.length)

        flash[:backup_codes] = codes
        redirect_to root_path(anchor: "backup-codes"), notice: t("backup_codes.generated")
      end

      private

        def require_actor
          redirect_to login_path unless current_actor
        end

        def refuse(message)
          redirect_to root_path(anchor: "backup-codes"), alert: message
        end
    end
  end
end
