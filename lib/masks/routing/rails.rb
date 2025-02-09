module Masks
  module Routing
    module Rails
      def mask(path, **args, &block)
        Masks::Routing::Middleware.mask(path, **args, &block)
      end

      def use_masks
        raise 'You cannot call "use_masks" twice' if @already_run

        @already_run = true

        masks = Masks.conf

        post "#{masks.graphql_endpoint}", to: "masks/graphql#execute"

        if masks.oidc?
          post "#{masks.token_endpoint}",
               as: :masks_token_endpoint,
               to: proc { |env| Masks::Openid::TokensController.new.call(env) }

          post "#{masks.userinfo_endpoint}",
               as: :masks_userinfo,
               to: proc { |env| Masks::Openid::TokensController.new.call(env) }

          post "#{masks.client_registration_endpoint}",
               as: :masks_client_registration,
               to: proc { |env| Masks::Openid::TokensController.new.call(env) }

          get "#{masks.client_issuer_endpoint}",
              as: :masks_client_issuer,
              to:
                redirect { |params, req|
                  "#{masks.client_well_known_endpoint}/openid-configuration".gsub(
                    ":client_id",
                    params[:client_id],
                  )
                }

          get "#{masks.client_well_known_endpoint}/openid-configuration",
              to: "masks/openid/discoveries#new",
              as: :masks_client_discovery

          get "#{masks.client_jwks_endpoint}",
              to: "masks/openid/discoveries#jwks",
              as: :masks_client_jwks
        end

        if masks.manage
          post "#{masks.manage_endpoint}/upload/logo",
               to: "masks/uploads/installation#logo"
          post "#{masks.manage_endpoint}/upload/favicon",
               to: "masks/uploads/installation#favicon"
          post "#{masks.manage_endpoint}/upload/client",
               to: "masks/uploads/client#create"
          post "#{masks.manage_endpoint}/upload/avatar",
               to: "masks/uploads/avatar#create"

          get "#{masks.manage_endpoint}",
              to: "masks/manage#index",
              as: :masks_manage
          get "#{masks.manage_endpoint}/*url", to: "masks/manage#index"
        end

        if masks.sso
          match "#{masks.sso_endpoint}/:provider_id",
                via: %w[get post],
                to: "masks/providers#callback",
                as: :masks_callback
        end

        get "#{masks.login}(/:client_id)",
            to: "masks/authorize#new",
            as: :masks_login
      end
    end
  end
end
