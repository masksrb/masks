require_relative "lib/masks/version"

Gem::Specification.new do |spec|
  spec.name = "masks"
  spec.version = Masks::VERSION
  spec.authors = [ "geiger" ]

  spec.summary = "Sign a Ruby or Rails app in against a masks issuer."
  spec.description = "Discovery, PKCE authorization, token exchange, and token " \
                     "verification against a masks issuer, with Rack middleware " \
                     "for a resource server and a Rails engine that mounts the " \
                     "consumer half of the code flow. The auth server itself " \
                     "stays standalone."
  spec.license = "MIT"
  spec.homepage = "https://github.com/masksrb/masks"
  spec.metadata = {
    "source_code_uri" => "https://github.com/masksrb/masks",
    "changelog_uri" => "https://github.com/masksrb/masks/blob/main/client/CHANGELOG.md",
    "rubygems_mfa_required" => "true"
  }
  spec.required_ruby_version = ">= 3.2"

  spec.files = Dir["lib/**/*.rb", "lib/**/*.tt", "app/**/*.rb", "app/**/*.erb",
                   "config/**/*.rb", "README.md", "CHANGELOG.md", "LICENSE"]
  spec.require_paths = [ "lib" ]

  spec.add_dependency "jwt", "~> 3.1"
end
