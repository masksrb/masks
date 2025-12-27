# frozen_string_literal: true

module Masks
  class RequestMiddleware
    APP = "masks.rack_app"

    def initialize(app)
      @app = app
    end

    def call(env)
      env[APP] = @app

      Masks::RequestController.action(:policy).call(env)
    end
  end
end
