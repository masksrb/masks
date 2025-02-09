require_relative "lib/masks/version"

Gem::Specification.new do |spec|
  Masks.gem("masks", spec)

  spec.summary = spec.description = "Simple, flexible auth for Rails and more."

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

  spec.add_dependency "activesupport", ">= 8.0.1"
  spec.add_dependency "activemodel", ">= 8.0.1"
  spec.add_dependency "chronic_duration", "~> 0.10.6"
  spec.add_dependency "device_detector", "~> 1.1"
  spec.add_dependency "openid_connect", "~> 2.3"
  spec.add_dependency "bcrypt", "~> 3.1"
  spec.add_dependency "fuzzyurl", "~> 0.9.0"
  spec.add_dependency "string-obfuscator", "~> 0.1.3"
  spec.add_dependency "addressable", "~> 2.8"
  spec.add_dependency "validates_host", "~> 1.3"
  spec.add_dependency "validate_url", "~> 1.0"
  spec.add_dependency "valid_email", "~> 0.2.1"
  spec.add_dependency "graphql-client", "~> 0.25.0"
end
