module Masks
  module Server
    class RevocationsController < ApplicationController
      include TokenPresented

      rate_limit to: 120, within: 1.minute,
                 by: -> { [ current_tenant.id, request.remote_ip ].join(":") },
                 with: -> {
                   render json: {
                     "error" => "slow_down",
                     "error_description" => "too many revocation requests from this address"
                   }, status: :too_many_requests
                 }

      def create
        client = authenticate_client!
        token = presented_token

        if token && token.client_id == client.id
          revoked = token.revoke!

          Event.record!(
            Event::TOKEN_REVOKED,
            actor: token.actor, by: nil, client: client,
            kind: token.class.name.underscore, revoked: revoked
          )
        end

        head :ok
      end
    end
  end
end
