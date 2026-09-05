class AccountController < ApplicationController
  def index
    @actor = current_actor
    @consents = @actor ? Consent.live.where(actor: @actor).includes(:client) : []
    @passkeys = @actor ? Passkey.where(actor: @actor).includes(:authenticator).newest_first : []
    @devices = @actor ? @actor.devices.newest_first : []
    @trusted = @actor ? DeviceFactor.live.where(actor: @actor).pluck(:device_id).to_set : Set.new
  end
end
