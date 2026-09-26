module Masks
  module Server
    class AccountController < ApplicationController
      RECENT = 20

      def index
        @actor = current_actor

        return redirect_to login_path if @actor.nil?

        @apps = Apps.held_by(@actor)
        @connections = Connection.live.where(actor: @actor).includes(:provider, live_delegations: :client).order(:created_at)
        @linkable = Linking.offered(@actor)
        @code_factors = CodeFactors::FACTORS.select do |factor|
          CodeFactors.held?(@actor, factor) || CodeFactors.offered?(@actor, factor)
        end
        @passkeys = Passkey.where(actor: @actor).includes(:authenticator).newest_first
        @devices = @actor.devices.newest_first
        @trusted = DeviceFactor.live.where(actor: @actor).pluck(:device_id).to_set
        @live = Session.live.where(device_id: @devices.map(&:id)).pluck(:device_id).to_set
        @events = Event.where(actor: @actor).newest_first.includes(:device).limit(RECENT)
      end
    end
  end
end
