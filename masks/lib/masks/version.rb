# frozen_string_literal: true

module Masks
  VERSION = Gem::Version.new('0.5.0')

  class Version
    # Required by zeitwerk
  end

  class << self
    def gem(name, spec)
      spec.name = name
      spec.version = Masks::VERSION
      spec.authors = ['masks']
      spec.email = ['masks@pm.me']
      spec.homepage = 'https://masks.pages.dev'
      spec.license = 'AGPL-3.0-or-later'
      spec.required_ruby_version = '>= 3.3'

      # prevent pushing this gem to rubygems.org. to allow pushes either set the "allowed_push_host"
      # to allow pushing to a single host or delete this section to allow pushing to any host.
      spec.metadata['allowed_push_host'] = 'https://rubygems.org'
      spec.metadata['homepage_uri'] ||= spec.homepage
      spec.metadata['source_code_uri'] ||= 'https://github.com/masksrb/masks'
      spec.metadata[
        'changelog_uri'
      ] ||= "#{spec.metadata['source_code_uri']}/blob/main/CHANGELOG.md"
    end
  end
end
