class HandshakesController < ApplicationController
  STORE = "handshake".freeze

  before_action :require_handshake
  before_action :require_actor

  def show
    @existing = Client.approved_for(@handshake.resource)
    @scopes = ResourceMetadata.describe(@handshake.resource, @handshake.scopes)
  end

  def create
    return redirect_to(@handshake.declined, allow_other_host: true) if params[:approve].blank?

    client = Client.approve!(@handshake, actor: current_actor)
    current_actor.grant!(@handshake.scopes)

    token = InitialAccessToken.mint!(
      actor: current_actor,
      client: client,
      scopes: Scopes.join(@handshake.scopes),
      audience: [ @handshake.resource ],
      redirect_uri: @handshake.return_to
    )

    session.delete(STORE)

    redirect_to @handshake.approved(token.secret, issuer: issuer.url), allow_other_host: true
  end

  private

    def require_handshake
      @handshake = requested || Handshake.from_session(session[STORE])

      return refuse("no connection request is in progress") if @handshake.nil?
      return refuse(@handshake.refusal) unless @handshake.usable?

      session[STORE] = @handshake.to_session
    end

    def requested
      return nil unless request.get? && params[:resource].present?

      Handshake.from_request(request)
    end

    def require_actor
      redirect_to login_path if current_actor.nil?
    end

    def refuse(description)
      @description = description

      render :refused, status: :bad_request
    end
end
