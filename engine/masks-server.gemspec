require_relative "lib/masks/server/version"

Gem::Specification.new do |spec|
  spec.name = "masks-server"
  spec.version = Masks::Server::VERSION
  spec.authors = [ "the masks authors" ]

  spec.summary = "The masks OpenID Connect provider, as a Rails engine."
  spec.description = "A multi-tenant OpenID Connect and OAuth 2.0 provider with a signing key per " \
                     "tenant, SAML, SCIM, passkeys, and a management API. Mount it at the root of " \
                     "an app of its own, or inside an existing Rails app."
  spec.license = "MIT"
  spec.homepage = "https://github.com/masksrb/masks"
  spec.metadata = {
    "source_code_uri" => "https://github.com/masksrb/masks",
    "changelog_uri" => "https://github.com/masksrb/masks/blob/main/server/CHANGELOG.md",
    "rubygems_mfa_required" => "true"
  }
  spec.required_ruby_version = ">= 3.4"

  spec.files = Dir["app/**/*", "config/**/*", "db/**/*", "lib/**/*"]
  spec.require_paths = [ "lib" ]

  spec.add_dependency "rails", "~> 8.1"
  spec.add_dependency "pg", "~> 1.1"
  spec.add_dependency "bcrypt", "~> 3.1.7"
  spec.add_dependency "jwt", "~> 3.1"
  spec.add_dependency "ruby-saml", "~> 1.18"
  spec.add_dependency "rack-oauth2", "~> 2.2"
  spec.add_dependency "openid_connect", "~> 2.3"
  spec.add_dependency "rqrcode", "~> 3.1"
  spec.add_dependency "rotp", "~> 6.3"
  spec.add_dependency "webauthn", "~> 3.4"
  spec.add_dependency "fido_metadata", "~> 0.5"
  spec.add_dependency "device_detector", "~> 1.1"
  spec.add_dependency "graphql", "~> 2.6"
  spec.add_dependency "premailer-rails", "~> 1.12"
  spec.add_dependency "ruby-vips", "~> 2.2"
end
