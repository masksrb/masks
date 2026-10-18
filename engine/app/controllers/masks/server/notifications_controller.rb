module Masks
  module Server
    class NotificationsController < ApplicationController
      before_action :require_actor
      before_action -> { reauthenticated!("notifications", t("notifications.again")) }

      def update
        was = current_actor.muted_notifications
        current_actor.update!(notifications: wanted)
        now = current_actor.muted_notifications

        muted = now - was
        unmuted = was - now

        if muted.any? || unmuted.any?
          Event.record!(Event::NOTIFICATIONS_CHANGED, actor: current_actor, muted: muted, unmuted: unmuted)
        end

        redirect_to "#{root_path}#notifications", notice: t("notifications.saved")
      end

      private

        def wanted
          Array(params[:notifications]).map(&:to_s) & Notifications::MUTABLE
        end

        def require_actor
          redirect_to login_path unless current_actor
        end
    end
  end
end
