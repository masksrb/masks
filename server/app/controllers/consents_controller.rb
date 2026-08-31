class ConsentsController < ApplicationController
  before_action :require_actor
  before_action :require_authorization

  def show
    @client = @authorization.client
    @audience = @authorization.audience
    @scopes = ResourceMetadata.describe(@audience, @authorization.scopes_for(current_actor))
  end

  def create
    if params[:approve].blank?
      return redirect_to @authorization.redirect_with(
        issuer: issuer,
        error: "access_denied",
        error_description: "the person signing in declined"
      ), allow_other_host: true
    end

    Consent.record!(
      actor: current_actor,
      client: @authorization.client,
      scopes: @authorization.scopes_for(current_actor),
      audience: @authorization.audience
    )

    redirect_to resume_authorization_path
  end

  private

    def require_actor
      redirect_to login_path if current_actor.nil?
    end

    def require_authorization
      @authorization = pending_authorization
      return redirect_to root_path if @authorization.nil?

      ClientPolicy.new(@authorization).call
      @authorization.validate!
    end
end
