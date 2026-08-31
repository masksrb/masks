module Masks
  module Rails
    module ProtectedResource
      extend ActiveSupport::Concern

      class_methods do
        def masks_protect!(**options)
          before_action(-> { masks_authenticate!(**options) }, **options.slice(:only, :except))
        end
      end

      def masks_resource
        @masks_resource ||= masks_config.resource_server_for(request)
      end

      def masks_claims
        @masks_claims if defined?(@masks_claims)
      end

      def masks_authenticate!(scope: nil, **)
        @masks_claims = masks_resource.authenticate(request.authorization, scope: scope)
      rescue Masks::Client::Challenge => e
        masks_challenge(e)
        false
      end

      def masks_authenticate(scope: nil)
        masks_resource.authenticate(request.authorization, scope: scope)
      rescue Masks::Client::Unauthenticated
        nil
      end

      def masks_challenge(error)
        error = Masks::Client::Unauthorized.new(error.to_s) unless error.is_a?(Masks::Client::Challenge)

        response.headers["WWW-Authenticate"] = masks_resource.challenge(error)
        response.headers["Cache-Control"] = "no-store"

        render json: {
          "error" => error.code || "invalid_token",
          "error_description" => error.description
        }, status: error.status
      end

      def masks_resource_metadata
        masks_resource.metadata
      end
    end
  end
end
