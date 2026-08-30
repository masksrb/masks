class RegistrationsController < ApplicationController
  skip_forgery_protection

  before_action :require_registration_token, except: :create

  METADATA = %i[
    client_name redirect_uris grant_types response_types scope
    token_endpoint_auth_method application_type
    client_uri logo_uri tos_uri policy_uri resources
  ].freeze

  def create
    client = Client.register!(attributes)

    render json: issued(client), status: :created
  rescue ActiveRecord::RecordInvalid => e
    render json: {
      "error" => "invalid_client_metadata",
      "error_description" => e.record.errors.full_messages.join("; ")
    }, status: :bad_request
  end

  def show
    render json: @client.metadata.merge("registration_client_uri" => registration_uri(@client))
  end

  def update
    @client.update!(attributes.except(:dynamic))

    render json: @client.metadata.merge("registration_client_uri" => registration_uri(@client))
  rescue ActiveRecord::RecordInvalid => e
    render json: {
      "error" => "invalid_client_metadata",
      "error_description" => e.record.errors.full_messages.join("; ")
    }, status: :bad_request
  end

  def destroy
    @client.update!(archived_at: Time.current)
    head :no_content
  end

  private

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
      token = request.authorization.to_s[/\ABearer (\S+)\z/, 1]
      @client = Client.by_registration_token(token)

      return if @client && @client.client_id == params[:client_id]

      response.headers["WWW-Authenticate"] = %(Bearer error="invalid_token")
      render json: {
        "error" => "invalid_token",
        "error_description" => "a registration access token is required"
      }, status: :unauthorized
    end
end
