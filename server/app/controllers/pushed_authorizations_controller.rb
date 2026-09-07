class PushedAuthorizationsController < ApplicationController
  include TokenPresented

  rate_limit to: 60, within: 1.minute,
             by: -> { [ current_tenant.id, request.remote_ip ].join(":") },
             with: -> { slow_down }

  def create
    client = authenticate_client!
    authorization = Authorization.from_request(request)

    check!(client, authorization)

    pushed = PushedRequest.push!(authorization)

    response.headers["Cache-Control"] = "no-store"
    response.headers["Pragma"] = "no-cache"

    render json: {
      "request_uri" => pushed.request_uri,
      "expires_in" => pushed.expires_in
    }, status: :created
  end

  private

    def check!(client, authorization)
      refuse!("a pushed request may not carry a request_uri of its own") if authorization.request_uri?
      refuse!("request objects are not supported") if authorization.request_object?

      refuse!("client_id is required") if authorization.client_id.blank?

      unless authorization.client_id == client.client_id
        refuse!("client_id does not match the authenticated client")
      end

      refuse!("response_type must be code") unless authorization.response_type == "code"
      refuse!("redirect_uri is required") if authorization.redirect_uri.blank?

      unless client.redirect_uri?(authorization.redirect_uri)
        refuse!("redirect_uri is not registered for this client")
      end

      authorization.validate!
    end

    def refuse!(description)
      raise Policy::Denied.new("invalid_request", description, status: :bad_request)
    end

    def slow_down
      render json: {
        "error" => "slow_down",
        "error_description" => "too many pushed requests from this address"
      }, status: :too_many_requests
    end
end
