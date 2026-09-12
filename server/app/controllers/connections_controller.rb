class ConnectionsController < ApplicationController
  include ResourceToken
  include RackOAuth2Endpoint

  PENDING = "connections".freeze
  TRACKED = 5
  WINDOW = 10.minutes

  skip_forgery_protection only: :index

  before_action :require_actor, only: %i[create callback destroy detach]

  def index
    with_access_token do |token|
      held = Connection.live.where(actor_id: token.actor&.id).includes(:provider)

      render json: {
        "connections" => held.select { |connection| token.scope_list.include?(connection.provider.release_scope) }
                             .map(&:to_h)
      }
    end
  end

  def create
    provider = active_provider!

    state = SecureRandom.urlsafe_base64(32)
    remember(state, provider)

    redirect_to provider.authorize_url(
      redirect_uri: callback_url_for(provider),
      state: state
    ), allow_other_host: true
  end

  def callback
    provider = active_provider!
    pending = claim(params[:state], provider)

    return refuse(pending, "state did not match a connection this browser began") if pending.nil?
    return refuse(pending, params[:error_description].presence || params[:error]) if params[:error].present?
    return refuse(pending, "the provider returned no code") if params[:code].blank?

    tokens = provider.redeem!(code: params[:code], redirect_uri: callback_url_for(provider))

    connection = Connection.record!(
      provider: provider,
      actor: current_actor,
      tokens: tokens,
      identity: provider.identify(tokens["access_token"])
    )

    Event.record!(
      Event::CONNECTION_LINKED,
      actor: current_actor, provider: provider.key
    )

    settle(pending, connection: connection.uuid)
  rescue Provider::Refused, Provider::Unreachable, ArgumentError => e
    refuse(pending, e.message)
  end

  def destroy
    connection = held(params[:id])

    return render json: { "error" => "invalid_target" }, status: :not_found if connection.nil?

    disconnect!(connection)

    render json: connection.to_h
  end

  def detach
    connection = held(params[:id])

    return redirect_to root_path, alert: t("connections.unknown") if connection.nil?

    disconnect!(connection)

    redirect_to root_path, notice: t("connections.disconnected", provider: connection.provider.name)
  end

  private

    def held(id)
      Connection.find_by(uuid: id, actor_id: current_actor.id)
    end

    def disconnect!(connection)
      connection.revoke!(reason: "revoked by #{current_actor.identifier}")

      Event.record!(
        Event::CONNECTION_UNLINKED,
        actor: current_actor, provider: connection.provider.key
      )
    end

    def require_actor
      return if current_actor

      session[:masks_return_to] = request.original_url if request.get? || request.head?

      redirect_to login_path
    end

    def active_provider!
      Provider.active.find_by(key: params[:provider].to_s) ||
        raise(Policy::Denied.new("invalid_target", "no provider named #{params[:provider]}", status: :not_found))
    end

    def callback_url_for(provider)
      "#{Current.origin}/connections/#{provider.key}/callback"
    end

    def remember(state, provider)
      held = session[PENDING] || {}

      held[state] = {
        "provider_id" => provider.id,
        "return_to" => permitted_return_to,
        "expires_at" => WINDOW.from_now.to_i
      }

      session[PENDING] = held.to_a.last(TRACKED).to_h
    end

    def claim(state, provider)
      held = session[PENDING] || {}
      pending = held.delete(state.to_s)
      session[PENDING] = held

      return nil if pending.nil?
      return nil unless pending["provider_id"] == provider.id
      return nil if pending["expires_at"].to_i <= Time.current.to_i

      pending
    end

    def permitted_return_to
      candidate = params[:return_to].presence
      return nil if candidate.nil?

      origin = origin_of(candidate)
      return nil if origin.nil?
      return candidate if origin == Current.origin
      return candidate if known_origins.include?(origin)

      nil
    end

    def known_origins
      @known_origins ||= Client.active.approved.flat_map do |client|
        [ client.client_uri, *client.redirect_uris ].filter_map { |uri| origin_of(uri) }
      end.uniq
    end

    def origin_of(value)
      uri = URI.parse(value.to_s)
      return nil if uri.scheme.blank? || uri.host.blank?

      port = ":#{uri.port}" unless uri.port == uri.default_port

      "#{uri.scheme}://#{uri.host}#{port}"
    rescue URI::InvalidURIError
      nil
    end

    def settle(pending, **query)
      destination = pending && pending["return_to"]

      return render json: { "connection" => query[:connection] } if destination.blank?

      redirect_to with_query(destination, query), allow_other_host: true
    end

    def refuse(pending, description)
      destination = pending && pending["return_to"]

      if destination.blank?
        return render json: { "error" => "connection_failed", "error_description" => description },
                      status: :bad_request
      end

      redirect_to with_query(destination, error: "connection_failed", error_description: description),
                  allow_other_host: true
    end

    def with_query(destination, query)
      uri = URI.parse(destination)
      merged = Rack::Utils.parse_query(uri.query).merge(query.compact.transform_keys(&:to_s))
      uri.query = URI.encode_www_form(merged)

      uri.to_s
    end
end
