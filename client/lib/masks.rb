# = \Masks
#
# Signs an application in against a masks issuer.
#
# The gem is two halves. Masks::Client is plain Ruby and speaks the protocol —
# discovery, PKCE, the code exchange, token verification. Masks::Rails mounts
# that flow into a \Rails app, and loads only when +Rails::Engine+ is already
# defined, so requiring this gem outside \Rails costs nothing.
#
#   issuer = Masks::Client.issuer("https://auth.example")
#   issuer.authorization_url(client_id: id, redirect_uri: uri)
#
# The provider itself is not in here. It is a deployable that holds a database
# and the per-tenant signing keys, and it stays standalone.
module Masks
end

require_relative "masks/version"
require_relative "masks/client"

require_relative "masks/rails" if defined?(::Rails::Engine)
