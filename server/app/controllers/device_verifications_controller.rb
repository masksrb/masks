class DeviceVerificationsController < ApplicationController
  UNKNOWN = "unknown".freeze
  DECLINED = "declined".freeze

  before_action :establish_device

  rate_limit to: Rails.configuration.masks.device_code_limit, within: 3.minutes,
             if: -> { params[:user_code].present? },
             by: -> { [ current_tenant.id, request.remote_ip ].join(":") },
             with: -> { asking(UNKNOWN, status: :too_many_requests) }

  def show
    return asking(params[:refused].presence) if params[:user_code].blank?

    grant = DeviceGrant.awaiting(params[:user_code])

    return asking(UNKNOWN) if grant.nil? || grant.answered?

    pending = track_request!(grant.authorization)

    return asking(UNKNOWN) if pending.consumed?

    login = advance(pending)

    return declined(grant, pending) if login.refused?
    return prompt(login) unless login.settled?

    approve!(grant, pending, login)
  end

  def create
    redirect_to device_verification_path(user_code: params[:user_code])
  end

  private

    def asking(refused = nil, status: :ok)
      @refused = refused

      render :show, status: status
    end

    def advance(pending)
      Login.new(
        store: session[LoginsController::STORE] ||= {},
        request: pending,
        session: current_session,
        device: current_device,
        rid: rid_for(pending)
      ).update
    end

    def prompt(login)
      @login = login

      render template: "logins/show"
    end

    def declined(grant, pending)
      PendingRequest.claim(rid_for(pending))
      grant.deny!

      Event.record!(Event::DEVICE_CODE_REFUSED, actor: current_actor, client: grant.client)

      asking(DECLINED)
    end

    def approve!(grant, pending, login)
      claimed = PendingRequest.claim(rid_for(pending))

      return asking(UNKNOWN) if claimed.nil?

      sign_in(login.actor, amr: login.amr) if current_session.nil?
      session.delete(LoginsController::STORE)

      grant.approve!(
        actor: current_actor,
        session: current_session,
        device: current_device,
        authenticated_at: login.authenticated_at || current_session&.authenticated_at,
        amr: login.amr.presence || current_session&.amr
      )

      Event.record!(
        Event::DEVICE_CODE_APPROVED,
        actor: current_actor, client: grant.client, scopes: grant.scopes_for(current_actor)
      )

      @client = grant.client

      render :approved
    end
end
