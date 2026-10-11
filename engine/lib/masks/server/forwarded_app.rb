module Masks
  module Server
    class ForwardedApp
      PATH = %r{/forward-auth(?:/callback)?\z}
      MOVED = %w[HTTP_X_FORWARDED_HOST HTTP_X_FORWARDED_URI HTTP_X_ORIGINAL_URL].freeze
      KEY = "masks.forwarded_app".freeze

      def initialize(app)
        @app = app
      end

      def call(env)
        env[KEY] = MOVED.to_h { |header| [ header, env.delete(header) ] }.compact if env["PATH_INFO"].to_s.match?(PATH)

        @app.call(env)
      end
    end
  end
end
