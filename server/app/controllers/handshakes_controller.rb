class HandshakesController < ApplicationController
  before_action :require_handshake
  before_action :require_actor
  before_action :require_pairing
  before_action :require_unclaimed_namespaces

  def show
    @scopes = ResourceMetadata.describe(@handshake.resource, @handshake.scopes)
    @granting = Namespace.prefixes(@handshake.scopes) - current_actor.scope_list
    @beneath = published_beneath(Namespace.prefixes(@handshake.scopes))
  end

  def create
    claimed = PendingHandshake.claim(hid_for(@pending))

    return refuse(t("handshakes.answered")) if claimed.nil?
    return redirect_to(@handshake.declined, allow_other_host: true) if params[:approve].blank?

    client = Client.approve!(@handshake, actor: current_actor)

    Event.record!(
      Event::CLIENT_APPROVED,
      actor: current_actor, client: client,
      name: client.name, resource: @handshake.resource
    )

    begin
      Namespace.claim!(@handshake, client: client, actor: current_actor)
    rescue Namespace::Taken => taken
      return refuse(taken.message)
    end

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
      return refuse(t("handshakes.none_in_progress")) if @pending.nil?
      return refuse(t("handshakes.answered")) if @pending.consumed?

      @handshake = @pending.handshake
      @existing = Client.approved_for(@handshake.resource)
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

    def require_pairing
      return if current_actor.holds?(Scopes::MANAGE)

      unless current_actor.holds?(Scopes::HANDSHAKE)
        return refuse(t("handshakes.not_permitted"))
      end

      if @existing && @existing.approved_by_id != current_actor.id
        return refuse(t("handshakes.already_connected", resource: @handshake.resource))
      end

      withheld = current_actor.withheld(@handshake.scopes)
      return if withheld.empty?

      refuse(t("handshakes.beyond_account", scopes: Scopes.join(withheld)))
    end

    def published_beneath(prefixes)
      return {} if prefixes.empty?

      ResourceMetadata.new(@handshake.resource).descriptions.select do |scope, _|
        prefixes.any? { |prefix| scope.start_with?(prefix) && scope.length > prefix.length }
      end
    end

    def require_unclaimed_namespaces
      refusal = Namespace.refusal(@handshake)
      return if refusal.nil?

      @console = manage_path

      refuse(refusal)
    end

    def refuse(description)
      @description = description

      render :refused, status: :bad_request
      nil
    end
end
