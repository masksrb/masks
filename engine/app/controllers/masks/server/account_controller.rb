module Masks
  module Server
    class AccountController < ApplicationController
      RECENT = 20

      def index
        @actor = current_actor

        return redirect_to login_path if @actor.nil?

        @apps = Apps.held_by(@actor)
        held = @actor.memberships.joins(:organization).merge(Organization.active)
                     .includes(:organization, :invited_by).order("organizations.name").to_a
        @invitations, @memberships = held.partition(&:pending?)
        ActiveRecord::Associations::Preloader.new(records: @memberships.map(&:organization), associations: { memberships: :actor }).call
        @connections = Connection.live.where(actor: @actor).includes(:provider, live_delegations: :client).order(:created_at)
        @linkable = Linking.offered(@actor)
        @code_factors = CodeFactors::FACTORS.select do |factor|
          CodeFactors.held?(@actor, factor) || CodeFactors.offered?(@actor, factor)
        end
        @passkeys = Passkey.where(actor: @actor).includes(:authenticator).newest_first
        @devices = @actor.devices.newest_first
        @trusted = DeviceFactor.live.where(actor: @actor).pluck(:device_id).to_set
        @live = Session.live.where(device_id: @devices.map(&:id)).pluck(:device_id).to_set
        @approver = DeviceFactor.satisfied?(device: current_device, actor: @actor)
        @approving = @approver && SignInApproval.waiting.find_by(id: session[SignInApprovalsController::HELD], actor_id: @actor.id)
        @events = Event.where(actor: @actor).newest_first.includes(:device).limit(RECENT)
        @fresh = current_session.fresh?
        @refusal = refusal(@actor)
      end

      def destroy
        actor = current_actor

        return redirect_to login_path if actor.nil?

        refused = refusal(actor)
        return refuse(t("account_deletion.#{refused}")) if refused

        unless current_session.fresh?
          sign_out
          return redirect_to login_path(return_to: root_path(anchor: "delete")), notice: t("account_deletion.again")
        end

        return refuse(t("account_deletion.mismatch")) unless params[:confirm].to_s.strip.casecmp?(actor.identifier.to_s)

        held = { uuid: actor.uuid, identifier: actor.identifier, reason: "account" }

        sign_out
        actor.destroy!

        Event.record!(Event::ACTOR_DELETED, by: nil, **held)

        redirect_to login_path, notice: t("account_deletion.deleted")
      end

      private

        def refusal(actor)
          return :manager if actor.last_manager?

          :provisioned if actor.external_id.present?
        end

        def refuse(message)
          redirect_to root_path(anchor: "delete"), alert: message
        end
    end
  end
end
