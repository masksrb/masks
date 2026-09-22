require "bcrypt"
require "jwt"
require "ruby-saml"
require "rack/oauth2"
require "openid_connect"
require "rqrcode"
require "rotp"
require "webauthn"
require "fido_metadata"
require "device_detector"
require "graphql"
require "premailer/rails"

module Masks
  PROTOCOL_VERSION = 1

  def self.to_bool(val, default: false)
    return default if val.nil?

    ActiveModel::Type::Boolean.new.cast(val)
  end

  module Server
    def self.table_name_prefix
      ""
    end
  end
end

require_relative "server/version"
require_relative "server/tenant_isolation"
require_relative "server/tenancy/job"
require_relative "server/tenancy/middleware"
require_relative "server/engine"
