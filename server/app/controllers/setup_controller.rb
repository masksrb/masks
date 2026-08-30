class SetupController < ApplicationController
  STORE = "pairing".freeze

  before_action :require_pairing
  before_action :require_actor

  def connect
    @existing = Client.approved_for(@pairing.resource)
    @scopes = Scopes.describe(@pairing.scopes)
  end

  def approve
    return redirect_to(@pairing.declined, allow_other_host: true) if params[:approve].blank?

    client = Client.approve!(@pairing, actor: current_actor)
    current_actor.grant!(@pairing.scopes)

    token = InitialAccessToken.mint!(
      actor: current_actor,
      client: client,
      scopes: Scopes.join(@pairing.scopes),
      audience: [ @pairing.resource ],
      redirect_uri: @pairing.return_to
    )

    session.delete(STORE)

    redirect_to @pairing.approved(token.secret, issuer: issuer.url), allow_other_host: true
  end

  private

    def require_pairing
      @pairing = requested || Pairing.from_session(session[STORE])

      return refuse("no connection request is in progress") if @pairing.nil?
      return refuse(@pairing.refusal) unless @pairing.usable?

      session[STORE] = @pairing.to_session
    end

    def requested
      return nil unless request.get? && params[:resource].present?

      Pairing.from_request(request)
    end

    def require_actor
      redirect_to login_path if current_actor.nil?
    end

    def refuse(description)
      @description = description

      render :refused, status: :bad_request
    end
end
