class DeviceAuthorizationsController < ApplicationController
  include RackOAuth2Endpoint
  include TokenPresented

  rate_limit to: 60, within: 1.minute,
             by: -> { [ current_tenant.id, request.remote_ip ].join(":") },
             with: -> { slow_down }

  def create
    client = authenticate_client!
    authorization = asked

    check!(client, authorization)

    grant = DeviceGrant.open!(authorization)

    Event.record!(Event::DEVICE_CODE_ISSUED, client: client, scopes: grant.scope_list)

    response.headers["Cache-Control"] = "no-store"
    response.headers["Pragma"] = "no-cache"

    render json: described(grant), status: :ok
  end

  private

    def asked
      Authorization.new(
        client_id: params[:client_id],
        redirect_uri: nil,
        response_type: nil,
        scope: params[:scope],
        resource: repeated("resource")
      )
    end

    def described(grant)
      spaced = UserCodes.spaced(grant.user_code)

      {
        "device_code" => grant.device_code,
        "user_code" => spaced,
        "verification_uri" => verification_uri,
        "verification_uri_complete" => "#{verification_uri}?#{URI.encode_www_form(user_code: spaced)}",
        "expires_in" => grant.expires_in,
        "interval" => grant.interval
      }
    end

    def verification_uri
      "#{issuer.url}#{device_verification_path}"
    end

    def check!(client, authorization)
      refuse!("client_id is required") if authorization.client_id.blank?

      unless authorization.client_id == client.client_id
        refuse!("client_id does not match the authenticated client")
      end

      DevicePolicy.new(authorization).call
    end

    def refuse!(description)
      raise Policy::Denied.new("invalid_request", description, status: :bad_request)
    end

    def slow_down
      render json: {
        "error" => "slow_down",
        "error_description" => "too many device requests from this address"
      }, status: :too_many_requests
    end
end
