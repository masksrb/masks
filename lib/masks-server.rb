require "masks"
require "graphql"
require "vite_rails"
require "phonelib"
require "fido_metadata"
require "webauthn"
require "validate_url"
require "valid_email"
require "validates_host"
require "apollo_upload_server"
require "active_record/session_store"
require "chronic_duration"
require "rotp"

require "omniauth"
require "omniauth-github"
require "omniauth-facebook"
require "omniauth-google-oauth2"
require "omniauth-apple"
require "omniauth-oauth2-generic"
require "omniauth_openid_connect"
require "omniauth/twitter2"

require "masks/engine"
require "masks/server_mode"
require "masks/prompt"

Dir[File.join(Masks::SRC, "lib/masks/prompts", "*.rb")].each do |file|
  require file
end

require "masks/adapter"

Dir[File.join(Masks::SRC, "lib/masks/adapters", "*.rb")].each do |file|
  require file
end

require "masks/endpoints/login_endpoint"
require "masks/endpoints/provider_endpoint"
