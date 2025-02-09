# frozen_string_literal: true

module Masks
  VERSION = Gem::Version.new("0.15.0")

  class Version
    # Required by zeitwerk
  end

  class << self
    def gem(name, spec)
      spec.name = name
      spec.version = Masks::VERSION
      spec.authors = ["masks"]
      spec.email = ["masks@pm.me"]
      spec.homepage = "https://github.com/masksrb/masks"
      spec.license = "MIT"

      # prevent pushing this gem to rubygems.org. to allow pushes either set the "allowed_push_host"
      # to allow pushing to a single host or delete this section to allow pushing to any host.
      spec.metadata[
        "allowed_push_host"
      ] = "todo: set to 'http://mygemserver.com'"
      spec.metadata["homepage_uri"] ||= spec.homepage
      spec.metadata["source_code_uri"] ||= "https://github.com/masksrb/#{name}"
      spec.metadata[
        "changelog_uri"
      ] ||= "#{spec.metadata["source_code_uri"]}/blob/main/CHANGELOG.md"
    end
  end
end
