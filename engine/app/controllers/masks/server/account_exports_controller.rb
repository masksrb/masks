module Masks
  module Server
    class AccountExportsController < ApplicationController
      rate_limit to: 5, within: 1.hour, only: :create,
                 by: -> { [ current_tenant.id, current_actor&.id || request.remote_ip ].join(":") },
                 with: -> { redirect_to root_path(anchor: "export"), alert: t("account_export.throttled") }

      def create
        actor = current_actor

        return redirect_to login_path if actor.nil?

        unless current_session.fresh?
          sign_out
          return redirect_to login_path(return_to: root_path(anchor: "export")), notice: t("account_export.again")
        end

        export = AccountExport.new(actor)
        body = export.to_json

        Event.record!(Event::ACCOUNT_EXPORTED, actor: actor)

        response.headers["Cache-Control"] = "no-store"
        send_data body, filename: export.filename, type: "application/json", disposition: "attachment"
      end
    end
  end
end
