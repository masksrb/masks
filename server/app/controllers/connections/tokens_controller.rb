module Connections
  class TokensController < ApplicationController
    include RackOAuth2Endpoint
    include ResourceToken

    skip_forgery_protection

    rate_limit to: 120, within: 1.minute,
               by: -> { [ current_tenant.id, request.remote_ip ].join(":") },
               with: -> { slow_down }

    def create
      with_access_token do |token|
        release = Release.new(token: token, connection_id: params[:connection_id]).validate!

        render json: release.issue!
      end
    rescue Connection::Revoked => e
      render json: { "error" => "invalid_grant", "error_description" => e.message },
             status: :bad_request
    rescue Provider::Unreachable => e
      render json: { "error" => "temporarily_unavailable", "error_description" => e.message },
             status: :service_unavailable
    end

    private

      def slow_down
        render json: {
          "error" => "slow_down",
          "error_description" => "too many release requests from this address"
        }, status: :too_many_requests
      end
  end
end
