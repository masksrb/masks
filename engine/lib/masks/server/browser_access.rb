module Masks
  module Server
    class BrowserAccess
      OPEN = %r{\A/(?:\.well-known/(?:openid-configuration|oauth-authorization-server|jwks\.json|oauth-protected-resource(?:/.*)?)|token|revoke|userinfo|avatars/.+)\z}
      ALLOWED_HEADERS = "Authorization, Content-Type, DPoP".freeze
      EXPOSED_HEADERS = "DPoP-Nonce, WWW-Authenticate".freeze
      PREFLIGHT_LIFETIME = 1.hour.to_i.to_s

      def initialize(app)
        @app = app
      end

      def call(env)
        return @app.call(env) unless env["HTTP_ORIGIN"] && OPEN.match?(env["PATH_INFO"].to_s)
        return preflight if env["REQUEST_METHOD"] == "OPTIONS"

        status, headers, body = @app.call(env)
        headers["access-control-allow-origin"] = "*"
        headers["access-control-expose-headers"] = EXPOSED_HEADERS

        [ status, headers, body ]
      end

      private
        def preflight
          [ 204, {
            "access-control-allow-origin" => "*",
            "access-control-allow-methods" => "GET, POST",
            "access-control-allow-headers" => ALLOWED_HEADERS,
            "access-control-max-age" => PREFLIGHT_LIFETIME
          }, [] ]
        end
    end
  end
end
