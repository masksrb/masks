source "https://rubygems.org"

# Specify your gem's dependencies in masks.gemspec.
gemspec name: "masks"
gemspec name: "masks-server"

source "https://rubygems.org"

gem "rails", "~> 8.0.1"
gem "puma", ">= 5.0"
gem "pg", "~> 1.1"
gem "sqlite3", "~> 2.4"
gem "tzinfo-data", platforms: %i[windows jruby]
gem "bootsnap", require: false
gem "solid_queue", "~> 1.1"
gem "solid_cache", "~> 1.0"
gem "solid_cable", "~> 3.0"
gem "mission_control-jobs", "~> 1.0"
gem "propshaft", "~> 1.1"
gem "foreman", "~> 0.88.1"
gem "rack-cors", "~> 2.0"
gem "premailer-rails", "~> 1.12"

gem "fido_metadata",
    git: "https://github.com/bdewater/fido_metadata",
    branch: "main"

group :development, :test do
  gem "brakeman", "~> 7.0"
  gem "debug", platforms: %i[mri windows], require: "debug/prelude"
  gem "rubocop-rails-omakase", require: false
  gem "prettier_print", "~> 1.2"
  gem "syntax_tree", "~> 6.2"
  gem "syntax_tree-haml", "~> 4.0"
  gem "syntax_tree-rbs", "~> 1.0"
  gem "database_cleaner-active_record", "~> 2.2"
  gem "simplecov", "~> 0.22.0"
  gem "simplecov-cobertura", "~> 2.1"
  gem "dotenv"
  gem "webmock", "~> 3.24"
end

group :development do
  gem "letter_opener", "~> 1.10"
  gem "web-console"
  gem "byebug", "~> 11.1"
  gem "graphiql-rails"
  gem "rdoc", "6.13.1"
  gem "rdoc-markdown"
  gem "rorvswild_theme_rdoc"
end

group :test do
  gem "capybara"
  gem "selenium-webdriver"
  gem "database_cleaner", "~> 2.1"
  gem "minitest-spec-rails", "~> 7.4"
end

# Monitoring
gem "stackprof"
gem "sentry-ruby"
gem "sentry-rails"
gem "newrelic_rpm", require: false

gem "yabeda", "~> 0.13.1"
gem "yabeda-rails", "~> 0.9.0"
gem "prometheus-client-mmap", "~> 1.1"
gem "yabeda-prometheus-mmap", "~> 0.4.0"
gem "yabeda-activerecord", "~> 0.1.1"
gem "yabeda-graphql", "~> 0.2.3"
gem "yabeda-puma-plugin", "~> 0.7.1"
gem "yabeda-http_requests", "~> 0.2.1"
gem "yabeda-activejob", "~> 0.6.0"

gem "colorize", "~> 1.1"
gem "thor", "~> 1.3"

gem "redcarpet", "~> 3.6"

gem "yard", "~> 0.9.37"
