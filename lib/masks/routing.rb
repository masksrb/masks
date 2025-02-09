module Masks
  module Routing
    class << self
      def install!
        ActionDispatch::Routing::Mapper.include Masks::Routing
      end

      def manage_path
        @manage_path
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
      raise 'You cannot call "use_masks" twice' if @already_run

      @already_run = true

      opts = {
        oidc: false,
        sso: "/sso/:provider_id",
        login: "/login",
        tokens: "/oidc/token",
        clients: "/oidc/client",
        userinfo: "/oidc/userinfo",
        issuer: "/oidc/:client_id",
        well_known: "/oidc/:client_id/.well-known",
        jwks: "/oidc/:client_id/jwks",
        manage: Masks::Routing.manage_path || "/masks",
        graphql: "/masks.graphql",
      }.merge(opts)

      Masks::Routing.manage_path = opts[:manage]
      Masks::Routing::Middleware.opts = opts

      if opts[:oidc]
        post "#{opts[:tokens]}",
             as: :masks_token_endpoint,
             to: proc { |env| Masks::Openid::TokensController.new.call(env) }

        post "#{opts[:userinfo]}",
             as: :masks_userinfo,
             to: proc { |env| Masks::Openid::TokensController.new.call(env) }

        post "#{opts[:clients]}",
             as: :masks_client_registration,
             to: proc { |env| Masks::Openid::TokensController.new.call(env) }

        get "#{opts[:issuer]}",
            as: :masks_client_issuer,
            to:
              redirect { |params, req|
                "#{opts[:well_known]}/openid-configuration".gsub(
                  ":client_id",
                  params[:client_id],
                )
              }

        get "#{opts[:well_known]}/openid-configuration",
            to: "masks/openid/discoveries#new",
            as: :masks_client_discovery

        get "#{opts[:issuer]}/styles.css",
            to: "masks/clients#css",
            as: :masks_client_css

        get "#{opts[:jwks]}",
            to: "masks/openid/discoveries#jwks",
            as: :masks_client_jwks
      end

      if opts[:graphql]
        post "#{opts[:graphql]}",
             to: "masks/graphql#execute",
             as: :masks_graphql
      end

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
        match opts[:sso],
              via: %w[get post],
              to: "masks/providers#callback",
              as: :masks_callback
      end

      match "#{opts[:login]}(/:client_id)",
            to: "masks/login#endpoint",
            as: :masks_login,
            via: %i[get post]
    end
  end
end
