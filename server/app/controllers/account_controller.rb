class AccountController < ApplicationController
  def index
    @actor = current_actor
    @consents = @actor ? Consent.live.where(actor: @actor).includes(:client) : []
    @passkeys = @actor ? Passkey.where(actor: @actor).newest_first : []
  end
end
