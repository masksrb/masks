require_relative "lib/masks/rails/version"

Gem::Specification.new do |spec|
  spec.name = "masks-rails"
  spec.version = Masks::Rails::VERSION
  spec.authors = [ "geiger" ]

  spec.summary = "Sign a Rails app in against a masks issuer."
  spec.description = "A Rails engine that mounts the consumer half of the OIDC " \
                     "code flow: start, callback, logout, and a controller concern. " \
                     "The auth server itself stays standalone."
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2"

  spec.files = Dir["lib/**/*.rb", "app/**/*.rb", "config/**/*.rb", "README.md"]
  spec.require_paths = [ "lib" ]

  spec.add_dependency "masks-client", ">= 0.1.0"
  spec.add_dependency "railties", ">= 7.1"
end
