module Scim
  class MetadataController < ApplicationController
    include ScimEndpoint

    def service_provider_config
      scim({
        "schemas" => [ Scim::SERVICE_PROVIDER_CONFIG ],
        "documentationUri" => "#{Rails.configuration.masks.docs_url}/concepts/provisioning/",
        "patch" => { "supported" => true },
        "bulk" => { "supported" => false, "maxOperations" => 0, "maxPayloadSize" => 0 },
        "filter" => { "supported" => true, "maxResults" => Scim::MAX_RESULTS },
        "changePassword" => { "supported" => true },
        "sort" => { "supported" => false },
        "etag" => { "supported" => true },
        "authenticationSchemes" => [
          {
            "type" => "oauthbearertoken",
            "name" => "Bearer token",
            "description" => "A provisioning token a manager issued, or an access token carrying #{Scopes::SCIM}",
            "primary" => true
          }
        ],
        "meta" => { "resourceType" => "ServiceProviderConfig", "location" => "#{scim_base}/ServiceProviderConfig" }
      })
    end

    def resource_types
      scim(listed([ user_type ]))
    end

    def resource_type
      raise Scim::Error.new(:not_found, "only User is provisioned here") unless params[:id] == "User"

      scim(user_type)
    end

    def schemas
      scim(listed([ user_schema ]))
    end

    def schema
      raise Scim::Error.new(:not_found, "that schema is not one this server speaks") unless params[:id] == Scim::USER

      scim(user_schema)
    end

    private

      def listed(resources)
        { "schemas" => [ Scim::LIST ], "totalResults" => resources.size, "startIndex" => 1,
          "itemsPerPage" => resources.size, "Resources" => resources }
      end

      def user_type
        {
          "schemas" => [ Scim::RESOURCE_TYPE ], "id" => "User", "name" => "User", "endpoint" => "/Users",
          "schema" => Scim::USER,
          "meta" => { "resourceType" => "ResourceType", "location" => "#{scim_base}/ResourceTypes/User" }
        }
      end

      def user_schema
        {
          "schemas" => [ Scim::SCHEMA ], "id" => Scim::USER, "name" => "User",
          "attributes" => [
            attribute("userName", required: true, uniqueness: "server"),
            attribute("externalId", uniqueness: "server", case_exact: true),
            attribute("displayName"),
            { "name" => "name", "type" => "complex", "multiValued" => false, "required" => false,
              "subAttributes" => %w[formatted givenName familyName middleName].map { |part| attribute(part) } },
            attribute("profileUrl"),
            attribute("locale"),
            attribute("timezone"),
            attribute("password", mutability: "writeOnly", returned: "never"),
            { "name" => "active", "type" => "boolean", "multiValued" => false, "required" => false,
              "mutability" => "readWrite", "returned" => "default" },
            multi("emails"), multi("phoneNumbers"), multi("photos")
          ],
          "meta" => { "resourceType" => "Schema", "location" => "#{scim_base}/Schemas/#{Scim::USER}" }
        }
      end

      def attribute(name, required: false, uniqueness: "none", case_exact: false, mutability: "readWrite", returned: "default")
        { "name" => name, "type" => "string", "multiValued" => false, "required" => required, "caseExact" => case_exact,
          "mutability" => mutability, "returned" => returned, "uniqueness" => uniqueness }
      end

      def multi(name)
        { "name" => name, "type" => "complex", "multiValued" => true, "required" => false,
          "subAttributes" => [ attribute("value"), attribute("type"), { "name" => "primary", "type" => "boolean" } ] }
      end
  end
end
