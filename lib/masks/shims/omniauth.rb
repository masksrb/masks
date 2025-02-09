module Masks
  module Shims
    class Omniauth
      class << self
        def request(*args, **opts)
          new(*args, **opts).request_phase
        end

        def callback(*args, **opts)
          new(*args, **opts).callback_phase
        end
      end

      attr_reader :provider, :query, :session, :status, :headers, :env

      def initialize(provider, query = {}, session: {})
        @provider = provider
        @query = query
        @session = session
      end

      def session_key
        ["sso", provider.key, omniauth.state].compact.join(":")
      end

      def request_phase
        @env = Masks::Shims.rack_env(:post, request_path, @query, session:)

        @status, @headers, _ = app.call(env)

        self
      end

      def callback_phase
        @env = Masks::Shims.rack_env(:post, callback_path, @query, session:)

        @status, @headers, _ = app.call(env)

        self
      end

      def auth
        env["omniauth.auth"]
      end

      def state
        session["omniauth.state"]
      end

      def redirect_uri
        headers["location"]
      end

      def callback_path
        "/sso/#{provider.key}"
      end

      def request_path
        "/sso/#{provider.key}/request"
      end

      def app
        @app ||=
          begin
            OmniAuth.config.request_validation_phase = nil
            OmniAuth.config.before_callback_phase = nil
            OmniAuth.config.full_host = Masks.conf.url.to_s

            default_opts = { request_path:, callback_path: }
            masks_provider = provider

            OmniAuth::Builder.new do
              self.provider(
                masks_provider.omniauth_strategy,
                *masks_provider.omniauth_args,
                **masks_provider.omniauth_opts.merge(default_opts),
              )

              run { |env| [500, { "content-type" => "text/plain" }, [""]] }
            end
          end
      end
    end
  end
end
