class SessionsController < ApplicationController
  rate_limit to: 10, within: 3.minutes, only: :create,
             by: -> { [ current_tenant.id, request.remote_ip ].join(":") },
             with: -> { too_many("Too many sign-in attempts. Wait a few minutes and try again.") }

  rate_limit to: 5, within: 3.minutes, only: :create, name: "identifier",
             by: -> { [ current_tenant.id, params[:identifier].to_s.downcase ].join(":") },
             with: -> { too_many("Too many sign-in attempts for that account.") }

  rate_limit to: 10, within: 3.minutes, only: :verify_second_factor,
             by: -> { [ current_tenant.id, request.remote_ip ].join(":") },
             with: -> { too_many("Too many codes. Wait a few minutes and try again.") }

  def new
    @authorization = pending_authorization
    redirect_to resume_authorization_path if current_actor && @authorization.nil?
  end

  def create
    actor = Actor.authenticate(params[:identifier], params[:password])

    if actor.nil?
      @authorization = pending_authorization
      flash.now[:alert] = "That identifier and password do not match."
      return render :new, status: :unprocessable_entity
    end

    if actor.otp?
      session[:pending_actor_id] = actor.id
      redirect_to second_factor_path
    else
      sign_in(actor)
      redirect_to after_sign_in_path
    end
  end

  def second_factor
    redirect_to login_path if pending_actor.nil?
  end

  def verify_second_factor
    actor = pending_actor
    return redirect_to login_path if actor.nil?

    unless actor.verify_otp(params[:code])
      flash.now[:alert] = "That code is not valid."
      return render :second_factor, status: :unprocessable_entity
    end

    session.delete(:pending_actor_id)
    sign_in(actor)
    redirect_to after_sign_in_path
  end

  def destroy
    sign_out
    redirect_to login_path
  end

  private

    def too_many(message)
      @authorization = pending_authorization
      flash.now[:alert] = message
      render :new, status: :too_many_requests
    end

    def pending_actor
      id = session[:pending_actor_id]
      Actor.find_by(id: id) if id
    end

    def after_sign_in_path
      session[:authorization].present? ? resume_authorization_path : root_path
    end
end
