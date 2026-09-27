module Masks
  module Server
    module ManageEndpoint
      extend ActiveSupport::Concern

      included do
        include RackOAuth2Endpoint
        include ResourceToken

        skip_forgery_protection
      end

      private

        def with_manage_token
          with_access_token(scope: ManageRoles::SCOPES) do |token|
            actor = token.actor

            next refuse_token("that token has no subject") if actor.nil?

            roles = ManageRoles.held(token.scope_list) & ManageRoles.held(actor.scope_list)

            next refuse_token("that actor no longer holds a manage role") if roles.empty?

            unless token.audience.include?(issuer.manage_resource)
              next refuse_token("that token was not issued for #{issuer.manage_resource}")
            end

            yield token, actor, roles
          end
        end
    end
  end
end
