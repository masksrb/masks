module Scim
  USER = "urn:ietf:params:scim:schemas:core:2.0:User".freeze
  ENTERPRISE_USER = "urn:ietf:params:scim:schemas:extension:enterprise:2.0:User".freeze
  LIST = "urn:ietf:params:scim:api:messages:2.0:ListResponse".freeze
  ERROR = "urn:ietf:params:scim:api:messages:2.0:Error".freeze
  PATCH = "urn:ietf:params:scim:api:messages:2.0:PatchOp".freeze
  SERVICE_PROVIDER_CONFIG = "urn:ietf:params:scim:schemas:core:2.0:ServiceProviderConfig".freeze
  RESOURCE_TYPE = "urn:ietf:params:scim:schemas:core:2.0:ResourceType".freeze
  SCHEMA = "urn:ietf:params:scim:schemas:core:2.0:Schema".freeze
  MEDIA_TYPE = "application/scim+json".freeze
  MAX_RESULTS = 200

  class Error < StandardError
    attr_reader :status, :scim_type

    def initialize(status, detail, scim_type: nil)
      super(detail)

      @status = status
      @scim_type = scim_type
    end

    def to_h
      {
        "schemas" => [ ERROR ],
        "status" => Rack::Utils.status_code(status).to_s,
        "scimType" => scim_type,
        "detail" => message
      }.compact
    end
  end

  def self.base(issuer)
    "#{issuer.url}/scim/v2"
  end
end
