require "rails"

module Masks
  # = Masks::Rails
  #
  # The consumer half: a \Rails engine that mounts the code flow into an
  # application, so signing in against a masks issuer is configuration rather
  # than a controller you write.
  #
  # It loads only when +Rails::Engine+ is already defined. Requiring the gem
  # from a plain Ruby process gets Masks::Client and nothing else.
  #
  # Three pieces do the work:
  #
  # [Configuration]    the issuer, credentials and routes, set once in an
  #                    initializer and validated on boot rather than on the
  #                    first request that needs them
  # [Authentication]   +masks_login_url+, the callback, and the session the
  #                    app reads +current_actor+ from
  # [ProtectedResource] the other direction — checking a bearer this app was
  #                    handed, for an API rather than a browser
  #
  # This engine is the client. It never runs in the same process as the
  # provider, which is a standalone deployable holding its own database.
  module Rails
  end
end

require_relative "version"
require_relative "client"
require_relative "rails/credentials"
require_relative "rails/configuration"
require_relative "rails/configurable"
require_relative "rails/authentication"
require_relative "rails/protected_resource"
require_relative "rails/engine"
