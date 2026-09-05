class AccountController < ApplicationController
  def index
    @actor = current_actor
    @consents = @actor ? Consent.live.where(actor: @actor).includes(:client) : []
    @passkeys = @actor ? Passkey.where(actor: @actor).includes(:authenticator).newest_first : []
  end
end
