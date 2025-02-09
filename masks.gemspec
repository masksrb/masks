require_relative "lib/masks/version"

Gem::Specification.new do |spec|
  spec.name = "masks"
  spec.version = Masks::VERSION
  spec.authors = ["geiger.to"]
  spec.email = ["git@geiger.to"]
  spec.homepage = "https://github.com/geiger-to/masks"
  spec.summary = "We all wear masks..."
  spec.description = "Simple, flexible auth for Rails and more."
  spec.license = "MIT"

  # Prevent pushing this gem to RubyGems.org. To allow pushes either set the "allowed_push_host"
  # to allow pushing to a single host or delete this section to allow pushing to any host.
  spec.metadata["allowed_push_host"] = "TODO: Set to 'http://mygemserver.com'"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/geiger-to/masks"
  spec.metadata[
    "changelog_uri"
  ] = "https://github.com/geiger-to/masks/blob/main/CHANGELOG.md"

  spec.files =
    Dir.chdir(File.expand_path(__dir__)) do
      Dir[
        "{app,config,db,lib,public}/**/*",
        "aaguids/combined_aaguid.json",
        "MIT-LICENSE",
        "Rakefile",
        "README.md"
      ]
    end

  spec.add_dependency "rails", ">= 8.0.1"
  spec.add_dependency "vite_rails"
  spec.add_dependency "recursive-open-struct", "~> 2.0"
  spec.add_dependency "chronic_duration", "~> 0.10.6"
  spec.add_dependency "device_detector", "~> 1.1"
  spec.add_dependency "openid_connect", "~> 2.3"
  spec.add_dependency "bcrypt", "~> 3.1"
  spec.add_dependency "fuzzyurl", "~> 0.9.0"
  spec.add_dependency "string-obfuscator", "~> 0.1.3"
  spec.add_dependency "addressable", "~> 2.8"
  spec.add_dependency "rotp", "~> 6.3"
  spec.add_dependency "rqrcode", "~> 2.2"
  spec.add_dependency "phonelib", "~> 0.10.3"
  spec.add_dependency "webauthn", "~> 3.1"
  spec.add_dependency "twilio-ruby", "~> 7.4"
  spec.add_dependency "image_processing", "~> 1.13"
  spec.add_dependency "csv", "~> 3.3"
  spec.add_dependency "geocoder", "~> 1.8"
  spec.add_dependency "graphql", "~> 2.4"
  spec.add_dependency "gli", "~> 2.22.2"
  spec.add_dependency "apollo_upload_server", "~> 2.1"
  spec.add_dependency "activerecord-session_store", "~> 2.1"
  spec.add_dependency "validates_host", "~> 1.3"
  spec.add_dependency "validate_url", "~> 1.0"
  spec.add_dependency "valid_email", "~> 0.2.1"
  spec.add_dependency "omniauth", "~> 2.1"
  spec.add_dependency "omniauth-github", "~> 2.0"
  spec.add_dependency "omniauth-facebook", "~> 10.0"
  spec.add_dependency "omniauth-google-oauth2", "~> 1.2"
  spec.add_dependency "omniauth-apple", "~> 1.3"
  spec.add_dependency "omniauth-oauth2-generic", "~> 0.2.8"
  spec.add_dependency "omniauth_openid_connect", "~> 0.8.0"
  spec.add_dependency "omniauth-twitter2", "~> 0.1.0"
end
