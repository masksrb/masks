require_relative "lib/masks/client/version"

Gem::Specification.new do |spec|
  spec.name = "masks-client"
  spec.version = Masks::Client::VERSION
  spec.authors = [ "geiger" ]

  spec.summary = "An OIDC client for masks."
  spec.description = "Discovery, PKCE authorization, token exchange, and token " \
                     "verification against a masks issuer."
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2"

  spec.files = Dir["lib/**/*.rb", "README.md"]
  spec.require_paths = [ "lib" ]

  spec.add_dependency "jwt", "~> 3.1"
end
