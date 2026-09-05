class SessionsController < ApplicationController
  skip_forgery_protection only: :destroy, if: -> { request.get? }

  def destroy
    logout = build_logout

    return confirm(logout) if asking?(logout)

    end_session(logout)
  rescue Logout::Refused => refusal
    render_refusal(refusal)
  end

  private

    def build_logout
      Logout.new(
        issuer: issuer,
        id_token_hint: params[:id_token_hint],
        client_id: params[:client_id],
        post_logout_redirect_uri: params[:post_logout_redirect_uri],
        state: params[:state]
      )
    end

    def asking?(logout)
      return false unless request.get? || request.head?
      return false if logout.verified?

      current_session.present?
    end

    def confirm(logout)
      @logout = logout
      @client = logout.client

      render :confirm
    end

    def end_session(logout)
      sign_out

      redirect_to(logout.redirect_to || login_path, allow_other_host: true)
    end

    def render_refusal(refusal)
      @error_code = refusal.code
      @error_description = refusal.message

      render "authorize/error", status: :bad_request
    end
end
