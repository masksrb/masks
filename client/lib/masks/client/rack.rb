module Masks
  module Client
    class Rack
      CLAIMS = "masks.claims".freeze
      ERROR = "masks.error".freeze

      def initialize(app, resource:, scope: nil, only: nil, optional: false)
        @app = app
        @resource = resource
        @scope = scope
        @only = only
        @optional = optional
      end

      def call(env)
        return @app.call(env) unless guards?(env)

        env[CLAIMS] = resource(env).authenticate(env["HTTP_AUTHORIZATION"], scope: @scope)

        @app.call(env)
      rescue Challenge => e
        return passthrough(env, e) if @optional && e.is_a?(Unauthenticated)

        refuse(resource(env), e)
      end

      private

        def guards?(env)
          return true if @only.nil?

          @only.call(env)
        end

        def passthrough(env, error)
          env[ERROR] = error

          @app.call(env)
        end

        def resource(env)
          @resource.respond_to?(:call) ? @resource.call(env) : @resource
        end

        def refuse(resource, error)
          body = JSON.generate(
            { "error" => error.code, "error_description" => error.description }.compact
          )

          [
            error.status,
            {
              "content-type" => "application/json",
              "cache-control" => "no-store",
              "www-authenticate" => resource.challenge(error)
            },
            [ body ]
          ]
        end
    end
  end
end
