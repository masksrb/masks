ENV["BUNDLE_GEMFILE"] ||= File.expand_path("../Gemfile", __dir__)
ENV["DEFAULT_TEST"] ||= "../test/{unit,integration}/**/*_test.rb"

require "bundler/setup"
