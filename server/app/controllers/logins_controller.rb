class LoginsController < ApplicationController
  STORE = "login".freeze
  VERIFYING = %w[password otp].freeze

  rate_limit to: Rails.configuration.masks.attempt_limit,
             within: 3.minutes, only: :update, if: -> { verifying? },
             by: -> { [ current_tenant.id, request.remote_ip ].join(":") },
             with: -> { too_many("too-many-attempts") }

  rate_limit to: Rails.configuration.masks.account_attempt_limit,
             within: 3.minutes, only: :update, name: "identifier", if: -> { verifying? },
             by: -> { [ current_tenant.id, session.dig(STORE, "identifier").to_s.downcase ].join(":") },
             with: -> { too_many("too-many-attempts-for-account") }

  def show
    return redirect_to after_login_path if current_actor && pending_authorization.nil?

    @login = run
    @login.warn!(*flash[:warnings]) if flash[:warnings].present?

    redirect_to after_login_path if @login.settled?
  end

  def update
    login = run(event: params[:event], updates: update_params)

    settle(login) if login.settled?

    respond_to do |format|
      format.html { resume(login) }
      format.json { render json: serialize(login) }
    end
  end

  def destroy
    run.start_over!
    sign_out

    respond_to do |format|
      format.html { redirect_to login_path }
      format.json { render json: serialize(run) }
    end
  end

  private

    def run(event: nil, updates: {})
      Login.new(
        store: session[STORE] ||= {},
        client: pending_authorization&.client,
        event: event,
        updates: updates
      ).update
    end

    def update_params
      params.permit(:identifier, :password, :code).to_h
    end

    def settle(login)
      return unless login.actor

      sign_in(login.actor)
      session.delete(STORE)
    end

    def serialize(login)
      login.as_json.merge("redirectTo" => (after_login_path if login.settled?))
    end

    def verifying?
      VERIFYING.include?(params[:event].to_s)
    end

    def resume(login)
      flash[:warnings] = login.warnings if login.warnings.any?

      redirect_to(login.settled? ? after_login_path : login_path)
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
      session[:authorization].present? ? resume_authorization_path : root_path
    end
end
