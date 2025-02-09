module Masks
  module Routing
    module Rails
      def mask(path, **args, &block)
        Masks::Routing::Middleware.mask(path, **args, &block)
      end

      def use_masks
        raise 'You cannot call "use_masks" twice' if @already_run

        @already_run = true

        Masks.mode.server? ? server_mode : client_mode
      end

      def client_mode
        conf = Masks.conf

        if conf.callback_endpoint
          get conf.callback_endpoint,
              to: "masks/callbacks#new",
              as: :masks_callback
        end

        Masks::Routing::Middleware.excluded_paths = [conf.callback_endpoint]
      end

      def server_mode
        client_mode

        conf = Masks.conf

        Masks::Routing::Middleware.excluded_paths = [
          conf.login_endpoint,
          conf.graphql_endpoint,
          conf.sso_endpoint,
          conf.client_issuer_endpoint,
          conf.client_registration_endpoint,
          conf.userinfo_endpoint,
          conf.token_endpoint,
          conf.manage_endpoint,
          conf.callback_endpoint,
        ]

        if conf.oidc_endpoints?
          post conf.token_endpoint,
               as: :masks_token_endpoint,
               to: proc { |env| Masks::Openid::TokensController.new.call(env) }

          post conf.userinfo_endpoint,
               as: :masks_userinfo,
               to: proc { |env| Masks::Openid::TokensController.new.call(env) }

          post conf.client_registration_endpoint,
               as: :masks_client_registration,
               to: proc { |env| Masks::Openid::TokensController.new.call(env) }

          get "#{conf.client_issuer_endpoint}/.well-known/openid-configuration",
              to: "masks/openid/discoveries#new",
              as: :masks_client_discovery

          get "#{conf.client_issuer_endpoint}/jwks",
              to: "masks/openid/discoveries#jwks",
              as: :masks_client_jwks
        end

        if conf.graphql_endpoint
          post conf.graphql_endpoint,
               to: "masks/graphql#execute",
               as: :masks_graphql
        end

        if conf.manage_endpoint
          post "#{conf.manage_endpoint}/upload/logo",
               to: "masks/uploads/installation#logo"
          post "#{conf.manage_endpoint}/upload/favicon",
               to: "masks/uploads/installation#favicon"
          post "#{conf.manage_endpoint}/upload/client",
               to: "masks/uploads/client#create"
          post "#{conf.manage_endpoint}/upload/avatar",
               to: "masks/uploads/avatar#create"

          get "#{conf.manage_endpoint}",
              to: "masks/manage#index",
              as: :masks_manage
          get "#{conf.manage_endpoint}/*url", to: "masks/manage#index"
        end

        if conf.sso_endpoint
          match conf.sso_endpoint,
                via: %w[get post],
                to: "masks/providers#callback",
                as: :masks_sso_callback
        end

        match "#{conf.login_endpoint}(/:client_id)",
              to: "masks/logins#update",
              as: :masks_login,
              via: %i[get post]
      end
    end
  end
end
