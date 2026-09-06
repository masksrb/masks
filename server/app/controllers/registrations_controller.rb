class RegistrationsController < ApplicationController
  skip_forgery_protection

  rate_limit to: Rails.configuration.masks.registration_limit, within: 10.minutes, only: :create,
             by: -> { [ current_tenant.id, request.remote_ip ].join(":") },
             with: -> {
               render json: {
                 "error" => "too_many_requests",
                 "error_description" => "too many registrations from this address"
               }, status: :too_many_requests
             }

  before_action :require_registration_token, except: :create

  METADATA = %i[
    client_name redirect_uris grant_types response_types scope
    post_logout_redirect_uris token_endpoint_auth_method application_type
    client_uri logo_uri tos_uri policy_uri resources
  ].freeze

  def create
    return redeem if bearer.present?

    client = Client.register!(attributes)

    Event.record!(Event::CLIENT_REGISTERED, client: client, name: client.name, dynamic: true)

    render json: issued(client), status: :created
  rescue ActiveRecord::RecordInvalid => e
    invalid_metadata(e.record.errors.full_messages.join("; "))
  rescue Client::ScopesUnavailable => e
    invalid_metadata(e.message)
  end

  def show
    render json: @client.metadata.merge("registration_client_uri" => registration_uri(@client))
  end

  def update
    @client.update!(described.merge(scope_updates))

    Event.record!(Event::CLIENT_UPDATED, client: @client, name: @client.name, dynamic: true)

    render json: @client.metadata.merge("registration_client_uri" => registration_uri(@client))
  rescue ActiveRecord::RecordInvalid => e
    invalid_metadata(e.record.errors.full_messages.join("; "))
  rescue Client::ScopesUnavailable => e
    invalid_metadata(e.message)
  end

  def destroy
    @client.update!(archived_at: Time.current)

    Event.record!(Event::CLIENT_ARCHIVED, client: @client, name: @client.name)

    head :no_content
  end

  private

    def redeem
      token = InitialAccessToken.claim(bearer)

      return unauthorized("that initial access token is not valid or has expired") if token&.client.nil?

      render json: issued(token.issue!), status: :created
    end

    def bearer
      request.authorization.to_s[/\ABearer (\S+)\z/, 1]
    end

    def body
      @body ||= begin
        parsed = JSON.parse(request.raw_post.presence || "{}")
        parsed.is_a?(Hash) ? parsed.symbolize_keys : {}
      rescue JSON::ParserError
        {}
      end
    end

    def attributes
      {
        name: body[:client_name],
        redirect_uris: body[:redirect_uris],
        post_logout_redirect_uris: body[:post_logout_redirect_uris],
        grant_types: body[:grant_types],
        response_types: body[:response_types],
        resources: body[:resources],
        scopes: body[:scope],
        token_endpoint_auth_method: body[:token_endpoint_auth_method],
        application_type: body[:application_type],
        client_uri: body[:client_uri],
        logo_uri: body[:logo_uri],
        tos_uri: body[:tos_uri],
        policy_uri: body[:policy_uri]
      }.compact
    end

    APPROVED = %i[redirect_uris post_logout_redirect_uris token_endpoint_auth_method resources].freeze

    def described
      held = attributes.except(:scopes, :dynamic)

      @client.approved? ? held.except(*APPROVED) : held
    end

    def scope_updates
      return {} if body[:scope].blank? || @client.approved?

      { allowed_scopes: Scopes.join(Client.bounded(body[:scope])) }
    end

    def invalid_metadata(description)
      render json: {
        "error" => "invalid_client_metadata",
        "error_description" => description
      }, status: :bad_request
    end

    def issued(client)
      client.metadata.merge(
        "client_secret" => client.secret,
        "client_secret_expires_at" => client.secret_expires_at&.to_i || 0,
        "registration_access_token" => client.registration_token,
        "registration_client_uri" => registration_uri(client)
      ).compact
    end

    def registration_uri(client)
      "#{issuer.url}/register/#{client.client_id}"
    end

    def require_registration_token
      @client = Client.by_registration_token(bearer)

      return if @client && @client.client_id == params[:client_id]

      unauthorized("a registration access token is required")
    end

    def unauthorized(description)
      response.headers["WWW-Authenticate"] = %(Bearer error="invalid_token")

      render json: {
        "error" => "invalid_token",
        "error_description" => description
      }, status: :unauthorized
    end
end
