module Masks
  module Server
    class ReceivedSignalsController < ApplicationController
      skip_forgery_protection

      rate_limit **Throttle.limits(:signal), only: :create,
                 by: -> { [ current_tenant.id, request.remote_ip ].join(":") },
                 with: Throttle.refused(:signal) { render json: { "err" => "invalid_request", "description" => "too many events from this address" }, status: :too_many_requests }

      def create
        ReceivedSignal.new(request.raw_post, issuer: issuer).receive!

        head :accepted
      rescue ReceivedSignal::Refused => e
        render json: { "err" => e.code, "description" => e.message }, status: :bad_request
      end
    end
  end
end
