module Masks
  class RequestController < ActionController::Base
    include Masks::Controller

    masks_policy :request

    skip_forgery_protection

    def policy
      # If we get here, all policies passed. We can call the rest
      # of the rack app and return its response. It's a funny inversion.
      status, headers, body = rack_app.call(request.env)

      self.status = status
      self.response_body = body

      headers.each { |k, v| response.headers[k] = v }
    end

    private

    def rack_app
      request.env[Masks::RequestMiddleware::APP]
    end
  end
end
