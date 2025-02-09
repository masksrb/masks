require_relative "lib/masks/version"

Gem::Specification.new do |spec|
  Masks.gem("masks-server", spec)

  spec.summary = "A simple, flexible auth server for Ruby/Rails"
  spec.description = <<-DESC
    This gem includes additional dependencies required for
    running the masks server inside a Rails app.
  DESC

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

  spec.add_dependency "rails", "~> 8.0.1"
  spec.add_dependency "vite_rails", "~> 3.0.1"
  spec.add_dependency "addressable", "~> 2.8"
  spec.add_dependency "rotp", "~> 6.3"
  spec.add_dependency "rqrcode", "~> 2.2"
  spec.add_dependency "phonelib", "~> 0.10.3"
  spec.add_dependency "webauthn", "~> 3.1"
  spec.add_dependency "twilio-ruby", "~> 7.4"
  spec.add_dependency "image_processing", "~> 1.13"
  spec.add_dependency "geocoder", "~> 1.8"
  spec.add_dependency "graphql", "~> 2.4"
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
