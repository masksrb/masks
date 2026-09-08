class NotificationsController < ApplicationController
  before_action :require_actor

  def update
    current_actor.update!(notifications: wanted)

    redirect_to "#{root_path}#notifications", notice: t("notifications.saved")
  end

  private

    def wanted
      Array(params[:notifications]).map(&:to_s) & Notifications::MAILED
    end

    def require_actor
      redirect_to login_path unless current_actor
    end
end
