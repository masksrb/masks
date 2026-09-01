class HandshakesController < ApplicationController
  before_action :require_handshake
  before_action :require_actor

  def show
    @existing = Client.approved_for(@handshake.resource)
    @scopes = ResourceMetadata.describe(@handshake.resource, @handshake.scopes)
  end

  def create
    claimed = PendingHandshake.claim(hid_for(@pending))

    return refuse("that connection request has already been answered") if claimed.nil?
    return redirect_to(@handshake.declined, allow_other_host: true) if params[:approve].blank?

    client = Client.approve!(@handshake, actor: current_actor)
    current_actor.grant!(@handshake.scopes)

    token = InitialAccessToken.mint!(
      actor: current_actor,
      client: client,
      parent: claimed,
      scopes: Scopes.join(@handshake.scopes),
      audience: [ @handshake.resource ],
      redirect_uri: @handshake.return_to
    )

    redirect_to @handshake.approved(token.secret, issuer: issuer.url), allow_other_host: true
  end

  private

    def require_handshake
      @pending = opening || pending_handshake(params[:hid])

      return if performed?
      return refuse("no connection request is in progress") if @pending.nil?
      return refuse("that connection request has already been answered") if @pending.consumed?

      @handshake = @pending.handshake
    end

    def opening
      return nil unless request.get? && params[:resource].present?

      handshake = Handshake.from_request(request)
      return refuse(handshake.refusal) unless handshake.usable?

      track_handshake!(handshake)
    end

    def require_actor
      redirect_to login_path if current_actor.nil?
    end

    def refuse(description)
      @description = description

      render :refused, status: :bad_request
      nil
    end
end
