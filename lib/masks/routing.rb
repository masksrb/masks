module Masks
  module Routing
    class << self
      def install!
        ActionDispatch::Routing::Mapper.include Masks::Routing
      end

      def manage_path
        @manage_path ||= "/masks"
      end

      def manage_path=(v)
        @manage_path = v
      end
    end

    class Middleware
      class << self
        def opts=(v)
          @opts = v
        end

        def opts
          @opts
        end

        def mask(path, **opts, &block)
          @masks ||= []
          @masks << { path:, block: block, **opts }
        end

        def masks
          @masks
        end
      end

      def initialize(app)
        @app = app
      end

      def call(env)
        # Not sure. works...
        Rails.application.reload_routes! unless Rails.env.production?
        Rails.application.reload_routes! unless Rails.env.production?

        masked = self.class.masks
        opts = self.class.opts

        request = ActionDispatch::Request.new(env)

        if masked && opts && opts.values.compact.exclude?(request.path)
          masked.each do |mask|
            path_match =
              request.path == mask[:path] ||
                request.path.start_with?(mask[:path])

            next unless path_match

            method_match =
              !mask[:method] || Array(mask[:method]).include?(request.method)

            next unless method_match

            begin
              Masks::Entries::Request.env(env)
            rescue Masks::LoggedOut => e
              return 302, { Location: e.redirect_uri }, "" if e.redirect_uri
            end
          end
        end

        @app.call(env)
      end
    end

    def mask(path, **args, &block)
      Masks::Routing::Middleware.mask(path, **args, &block)
    end

    def use_masks(**opts)
      opts = {
        oidc: false,
        manage: Masks::Routing.manage_path,
        token: "/token",
        jwks: "/jwks",
        sso: "/sso",
        login: "/login",
        graphql: "/login.graphql",
      }.merge(opts)

      Masks::Routing.manage_path = opts[:manage]
      Masks::Routing::Middleware.opts = opts

      post "#{opts[:graphql]}", to: "masks/graphql#execute"

      if opts[:manage]
        post "#{opts[:manage]}/upload/logo",
             to: "masks/uploads/installation#logo"
        post "#{opts[:manage]}/upload/favicon",
             to: "masks/uploads/installation#favicon"
        post "#{opts[:manage]}/upload/client", to: "masks/uploads/client#create"
        post "#{opts[:manage]}/upload/avatar", to: "masks/uploads/avatar#create"

        get "#{opts[:manage]}", to: "masks/manage#index", as: :masks_manage
        get "#{opts[:manage]}/*url", to: "masks/manage#index"
      end

      if opts[:sso]
        match "#{opts[:sso]}/:provider_id",
              via: %w[get post],
              to: "masks/providers#callback",
              as: :masks_callback
      end

      get "#{opts[:login]}(/:client_id)",
          to: "masks/authorize#new",
          as: :masks_login

      if opts[:oidc]
        post "#{opts[:token]}",
             to: proc { |env| Masks::TokensController.new.call(env) }

        get "/.well-known/:client/openid-configuration",
            to: "masks/oidc/discoveries#new",
            as: :masks_oidc_discovery

        get "#{opts[:jwks]}/:client",
            to: "masks/oidc/discoveries#jwks",
            as: :masks_oidc_jwks
      end
    end
  end
end
