module Masks
  module Rails
    module ProtectedResource
      extend ActiveSupport::Concern
      include Masks::Rails::Configurable
      include Masks::Rails::Privileged

      included do
        rescue_from Masks::Client::ReplayUnavailable, with: :masks_unavailable if respond_to?(:rescue_from)
      end

      def masks_resource
        @masks_resource ||= masks_config.resource_server_for(request)
      end

      def masked
        return (defined?(super) ? super : Masked.nobody(masks_config)) unless defined?(@masks_token_claims)

        @masked_by_token ||= Masked.new(
          claims: @masks_token_claims, scopes: @masks_token_claims.scopes, config: masks_config, signed_in: true,
          access_token: masks_resource.token(request.authorization), expires_at: @masks_token_claims.expires_at
        )
      end

      def masks_authenticate(scope: nil, role: nil, organization: nil)
        masks_resource.authenticate(request.authorization, scope: scope, role: role, organization: organization,
                                                           **masks_proof)
      rescue Masks::Client::Unauthenticated
        nil
      end

      def masks_proof
        { proof: request.headers["DPoP"], method: request.request_method, url: "#{request.base_url}#{request.path}" }
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

      def masks_unavailable
        response.headers["Cache-Control"] = "no-store"

        render json: {
          "error" => "temporarily_unavailable",
          "error_description" => "the token could not be checked"
        }, status: :service_unavailable
      end

      def masks_resource_metadata
        masks_resource.metadata
      end

      private

        def masks_authorize_token!(privileges)
          claims = masks_resource.authenticate(request.authorization, scope: privileges.flat_map(&:scopes).uniq,
                                                                      **masks_proof)

          privileges.each do |privilege|
            next if privilege.roles.empty? && privilege.organization.nil?

            claims.member!(*privilege.roles, organization: privilege.organization)
          end

          @masks_token_claims = claims
          true
        rescue Masks::Client::Challenge => e
          masks_challenge(e)
          false
        end
    end
  end
end
