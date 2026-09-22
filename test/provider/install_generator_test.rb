require_relative "test_helper"
require "rails/generators/test_case"
require "generators/masks/server/install/install_generator"

class InstallGeneratorTest < Rails::Generators::TestCase
  tests Masks::Server::Generators::InstallGenerator
  destination File.join(Dir.tmpdir, "masks-server-install")

  setup do
    prepare_destination
    FileUtils.mkdir_p(File.join(destination_root, "config"))
    File.write(File.join(destination_root, "config/routes.rb"), "Rails.application.routes.draw do\nend\n")
  end

  test "engine mode mounts masks at a path, with a database and a tenant of its own" do
    run_generator %w[--at /auth]

    assert_file "config/initializers/masks_server.rb" do |initializer|
      assert_match "config.masks.mode = :engine", initializer
      assert_match "config.masks.database = :masks", initializer
      assert_match 'config.masks.tenant = "app"', initializer
    end
    assert_file "config/routes.rb", %r{mount Masks::Server::Engine, at: "/auth"}
  end

  test "engine mode on a subdomain mounts masks at the root of that host" do
    run_generator %w[--host auth.example.com]

    assert_file "config/routes.rb",
                %r{constraints\(host: "auth.example.com"\) \{ mount Masks::Server::Engine, at: "/" \}}
  end

  test "server mode mounts masks at the root and keeps it in the primary database" do
    run_generator %w[--mode server]

    assert_file "config/initializers/masks_server.rb" do |initializer|
      assert_match "config.masks.mode = :server", initializer
      assert_no_match "config.masks.database", initializer
    end
    assert_file "config/routes.rb", %r{mount Masks::Server::Engine, at: "/"}
  end
end
