module ManageEndpoint
  extend ActiveSupport::Concern

  included do
    include RackOAuth2Endpoint
    include ResourceToken

    skip_forgery_protection
  end

  private

    def with_manage_token
      with_access_token(scope: Scopes::MANAGE) do |token|
        actor = token.actor

        next refuse_token("that token has no subject") if actor.nil?

        unless actor.scope_list.include?(Scopes::MANAGE)
          next refuse_token("that actor no longer holds #{Scopes::MANAGE}")
        end

        unless token.audience.include?(issuer.manage_resource)
          next refuse_token("that token was not issued for #{issuer.manage_resource}")
        end

        yield token, actor
      end
    end
end
