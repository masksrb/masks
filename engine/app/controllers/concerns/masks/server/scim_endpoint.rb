module Masks
  module Server
    module ScimEndpoint
      extend ActiveSupport::Concern

      included do
        include ResourceToken

        skip_forgery_protection

        rate_limit to: 600, within: 1.minute,
                   by: -> { [ current_tenant.id, request.remote_ip ].join(":") },
                   with: -> { scim_error(Scim::Error.new(:too_many_requests, "too many provisioning requests from this address")) }

        rescue_from Scim::Error, with: :scim_error
        before_action :require_provisioner
      end

      private

        def require_provisioner
          scheme, secret = credentials

          raise Scim::Error.new(:unauthorized, "a bearer token is required") unless scheme.to_s.casecmp?("Bearer") && secret.present?

          return if provisioning_token(secret) || scim_access_token(secret)

          raise Scim::Error.new(:unauthorized, "that token is not one this tenant provisions with")
        end

        def provisioning_token(secret)
          ProvisioningToken.redeem(secret)&.tap(&:used!)
        end

        def scim_access_token(secret)
          token = held_token(secret)

          token if token && !token.bound? && token.scope_list.include?(Scopes::SCIM) && token.audience.include?(scim_base)
        end

        def scim_base
          Scim.base(issuer)
        end

        def document
          @document ||= begin
            parsed = JSON.parse(request.raw_post.presence || "{}")

            raise Scim::Error.new(:bad_request, "the body must be a JSON object", scim_type: "invalidSyntax") unless parsed.is_a?(Hash)

            parsed
          rescue JSON::ParserError
            raise Scim::Error.new(:bad_request, "the body is not JSON", scim_type: "invalidSyntax")
          end
        end

        def scim(body, status: :ok)
          render json: body, status: status, content_type: Scim::MEDIA_TYPE
        end

        def scim_error(error)
          response.headers["WWW-Authenticate"] = %(Bearer realm="#{scim_base}") if error.status == :unauthorized

          scim(error.to_h, status: error.status)
        end
    end
  end
end
