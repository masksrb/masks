module Manage
  class GraphqlController < ApplicationController
    include RackOAuth2Endpoint
    include BearerResource

    skip_forgery_protection

    def execute
      with_access_token(scope: Scopes::MANAGE) do |token|
        actor = token.actor

        next refuse_token("that token has no subject") if actor.nil?

        unless actor.scope_list.include?(Scopes::MANAGE)
          next refuse_token("that actor no longer holds #{Scopes::MANAGE}")
        end

        unless token.audience.include?(issuer.manage_resource)
          next refuse_token("that token was not issued for #{issuer.manage_resource}")
        end

        render json: ManageSchema.execute(
          params[:query],
          variables: variables,
          operation_name: params[:operationName],
          context: { actor: actor, client: token.client, token: token }
        )
      end
    end

    private

      def variables
        case params[:variables]
        when String then JSON.parse(params[:variables].presence || "{}")
        when ActionController::Parameters then params[:variables].to_unsafe_h
        when Hash then params[:variables]
        else {}
        end
      rescue JSON::ParserError
        {}
      end
  end
end
