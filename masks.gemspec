require_relative "lib/masks/version"

Gem::Specification.new do |spec|
  Masks.gem("masks", spec)

  spec.summary = "Simple, flexible auth for Ruby/Rails"
  spec.description = [
    "This gem includes helpers for communication with a masks server.",
    "It can also be used to host a masks server inside any Rails app, as a Rails engine.",
  ].join("\n")

  # Prevent pushing this gem to RubyGems.org. To allow pushes either set the "allowed_push_host"
  # to allow pushing to a single host or delete this section to allow pushing to any host.
  spec.files =
    Dir.chdir(File.expand_path(__dir__)) do
      Dir["{config,lib}/**/*", "LICENSE", "README.md"]
    end

  spec.add_dependency "activesupport", "~> 8.0.1"
  spec.add_dependency "activemodel", "~> 8.0.1"
  spec.add_dependency "chronic_duration", "~> 0.10.6"
  spec.add_dependency "device_detector", "~> 1.1"
  spec.add_dependency "openid_connect", "~> 2.3"
  spec.add_dependency "bcrypt", "~> 3.1"
  spec.add_dependency "fuzzyurl", "~> 0.9.0"
  spec.add_dependency "string-obfuscator", "~> 0.1.3"
  spec.add_dependency "addressable", "~> 2.8"
  spec.add_dependency "graphql-client", "~> 0.25.0"
  spec.add_dependency "colorize", "~> 1.1"

  spec.executables = ["masks"]
end
