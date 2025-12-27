# frozen_string_literal: true

require_relative 'lib/masks/version'

Gem::Specification.new do |spec|
  Masks.gem('masks', spec)

  spec.summary = 'Simple, modular auth for the open web. Built with Rails.'
  spec.description = [
    'This gem includes helpers for communication with a masks server.',
    'It can also be used to host a masks server inside any Rails app, as a Rails engine.'
  ].join("\n")

  # Prevent pushing this gem to RubyGems.org. To allow pushes either set the "allowed_push_host"
  # to allow pushing to a single host or delete this section to allow pushing to any host.
  spec.files =
    Dir.chdir(File.expand_path(__dir__)) do
      Dir['{config,lib,app}/**/*', 'LICENSE', 'README.md']
    end

  spec.add_dependency 'addressable', '~> 2.8'
  spec.add_dependency 'alba', '~> 3.6.0'
  spec.add_dependency 'apollo_upload_server', '~> 2.1'
  spec.add_dependency 'bcrypt', '~> 3.1'
  spec.add_dependency 'chronic_duration', '~> 0.10.6'
  spec.add_dependency 'colorize', '~> 1.1'
  spec.add_dependency 'device_detector', '~> 1.1'
  spec.add_dependency 'fuzzyurl', '~> 0.9.0'
  spec.add_dependency 'graphql', '~> 2.4'
  spec.add_dependency 'openid_connect', '~> 2.3'
  spec.add_dependency 'phonelib', '~> 0.10.3'
  spec.add_dependency 'rails', '~> 8.1.1'
  spec.add_dependency 'string-obfuscator', '~> 0.1.3'
  spec.add_dependency 'validates_host', '~> 1.3'
  spec.add_dependency 'validate_url', '~> 1.0'
  spec.add_dependency 'valid_email', '~> 0.2.1'
  spec.add_dependency 'vite_rails', '~> 3.0.1'

  spec.executables = ['masks']
end
