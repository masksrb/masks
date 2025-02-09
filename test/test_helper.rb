# Configure Rails Environment
ENV["RAILS_ENV"] = "test"

require_relative "../server/config/environment"

ActiveRecord::Migrator.migrations_paths = [
  File.expand_path("../server/db/migrate", __dir__),
]
ActiveRecord::Migrator.migrations_paths << File.expand_path(
  "../db/migrate",
  __dir__,
)

require_relative "cases/masks_test_case"
require_relative "cases/auth_test_case"
require_relative "cases/graphql_test_case"

require "database_cleaner/active_record"
require "rails/test_help"
require "byebug"
require "simplecov"
require "simplecov-cobertura"
require "webmock/minitest"

SimpleCov.formatter = SimpleCov::Formatter::CoberturaFormatter
SimpleCov.start "rails" do
  enable_coverage :branch
end

DatabaseCleaner.strategy = :deletion

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    # parallelize(workers: :number_of_processors)

    teardown do
      DatabaseCleaner.clean
      Mail::TestMailer.deliveries.clear
    end
  end
end
