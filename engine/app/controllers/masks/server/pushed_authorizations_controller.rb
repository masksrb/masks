module Masks
  module Server
    class PushedAuthorizationsController < ApplicationController
      include TokenPresented

      rate_limit to: 60, within: 1.minute,
                 by: -> { [ current_tenant.id, request.remote_ip ].join(":") },
                 with: -> { slow_down }

      def create
        client = authenticate_client!
        authorization = unpacked(client, Authorization.from_request(request))

        check!(client, authorization)

        pushed = PushedRequest.push!(authorization)

        no_store!

        render json: {
          "request_uri" => pushed.request_uri,
          "expires_in" => pushed.expires_in
        }, status: :created
      end

      private

        def unpacked(client, authorization)
          refuse!("a pushed request may not carry a request_uri of its own") if authorization.request_uri?

          return authorization unless authorization.request_object?

          unless authorization.client_id.blank? || authorization.client_id == client.client_id
            refuse!("client_id does not match the authenticated client")
          end

          RequestObject.new(authorization.request_object, client: client, client_id: client.client_id, issuer: issuer).authorization
        rescue RequestObject::Refused => e
          raise Policy::Denied.new("invalid_request_object", e.message)
        end

        def check!(client, authorization)
          refuse!("this client has to sign its authorization requests") if client.require_signed_request_object? && !authorization.signed?

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

        def slow_down
          render json: {
            "error" => "slow_down",
            "error_description" => "too many pushed requests from this address"
          }, status: :too_many_requests
        end
    end
  end
end
