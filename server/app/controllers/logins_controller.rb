class LoginsController < ApplicationController
  STORE = "login".freeze
  VERIFYING = %w[password otp backup setup].freeze

  skip_forgery_protection

  rate_limit to: Rails.configuration.masks.attempt_limit,
             within: 3.minutes, only: :update, if: -> { verifying? },
             by: -> { [ current_tenant.id, request.remote_ip ].join(":") },
             with: -> { too_many("too-many-attempts") }

  rate_limit to: Rails.configuration.masks.account_attempt_limit,
             within: 3.minutes, only: :update, name: "identifier", if: -> { verifying? },
             by: -> { [ current_tenant.id, session.dig(STORE, "identifier").to_s.downcase ].join(":") },
             with: -> { too_many("too-many-attempts-for-account") }

  rate_limit to: Rails.configuration.masks.recovery_limit,
             within: 15.minutes, only: :update, name: "recovery",
             if: -> { params[:event].to_s == "forgot-password" },
             by: -> { [ current_tenant.id, request.remote_ip ].join(":") },
             with: -> { too_many("too-many-attempts") }

  rate_limit to: Rails.configuration.masks.attempt_limit,
             within: 3.minutes, only: :provider, name: "provider",
             by: -> { [ current_tenant.id, request.remote_ip ].join(":") },
             with: -> { too_many("too-many-attempts") }

  before_action :verify_authenticity_token
  before_action :establish_device, only: %i[update provider]

  def show
    return redirect_to after_login_path if current_actor && pending.nil?

    @login = run
    @login.warn!(*flash[:warnings]) if flash[:warnings].present?

    redirect_to after_login_path if @login.settled?
  end

  def update
    login = run(event: params[:event], updates: update_params)

    settle(login) if login.settled? && pending.nil?

    respond_to do |format|
      format.html { resume(login) }
      format.json { render json: serialize(login) }
    end
  end

  def provider
    login = run(event: "provider:callback", updates: callback_params)

    settle(login) if login.settled? && pending.nil?

    resume(login)
  end

  def destroy
    login = run
    login.start_over!
    sign_out

    respond_to do |format|
      format.html { resume(login) }
      format.json { render json: serialize(run) }
    end
  end

  private

    def pending
      return @pending if defined?(@pending)

      @pending = pending_request(resolved_rid)
    end

    def resolved_rid
      @resolved_rid ||= params[:rid].presence ||
        session.dig(STORE, LoginStates::Provider::HELD, "rid").presence
    end

    def callback_params
      params.permit(:code, :state, :error, :error_description)
            .to_h
            .merge("provider" => params[:key])
    end

    def run(event: nil, updates: {})
      Login.new(
        store: session[STORE] ||= {},
        request: pending,
        session: current_session,
        device: current_device,
        rid: resolved_rid,
        event: event,
        updates: updates
      ).update
    end

    def update_params
      params.permit(*Login.permitted_updates).to_h
    end

    def settle(login)
      return unless login.actor

      sign_in(login.actor, amr: login.amr)
      session.delete(STORE)
    end

    def serialize(login)
      login.as_json.merge("redirectTo" => next_location(login))
    end

    def verifying?
      VERIFYING.include?(params[:event].to_s)
    end

    def resume(login)
      flash[:warnings] = login.warnings if login.warnings.any?

      redirect_to next_location(login) || login_path, allow_other_host: true
    end

    def next_location(login)
      return login.redirect_to if login.redirect_to.present?
      return refuse_device(pending) if login.refused? && pending&.device?
      return deny(pending, login.refusal.error, login.refusal.description) if login.refused? && pending
      return device_url_for(pending) if pending&.device?
      return authorize_url_for(pending) if pending
      return after_login_path if login.settled?

      nil
    end

    def too_many(warning)
      login = run
      login.warn!(warning)

      respond_to do |format|
        format.html { resume(login) }
        format.json { render json: serialize(login), status: :too_many_requests }
      end
    end

    def after_login_path
      pending = latest_handshake
      return handshake_url_for(pending) if pending

      root_path
    end
end
