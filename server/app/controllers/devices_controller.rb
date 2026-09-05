class DevicesController < ApplicationController
  before_action :require_actor

  def update
    return refuse("There is no such device on this account.") if device.nil?

    device.update!(name: params[:name].to_s.strip.presence)

    redirect_to root_path, notice: "Device renamed."
  end

  def destroy
    return refuse("There is no such device on this account.") if device.nil?

    device.sign_out!

    if device == current_device
      cookies.delete(:masks_session)
      return redirect_to login_path, notice: "That device has been signed out."
    end

    redirect_to root_path, notice: "That device has been signed out."
  end

  private

    def device
      @device ||= current_actor.devices.find_by(id: params[:id])
    end

    def require_actor
      redirect_to login_path unless current_actor
    end

    def refuse(message)
      redirect_to root_path, alert: message
    end
end
