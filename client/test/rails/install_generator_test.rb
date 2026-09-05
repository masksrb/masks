require_relative "test_helper"
require "rails/generators"
require "rails/generators/test_case"
require "generators/masks/install/install_generator"

class InstallGeneratorTest < ::Rails::Generators::TestCase
  tests Masks::Generators::InstallGenerator
  destination File.join(Dir.tmpdir, "masks-install-#{SecureRandom.hex(4)}")

  setup do
    prepare_destination
    FileUtils.mkdir_p(File.join(destination_root, "config"))
    File.write(File.join(destination_root, "config", "routes.rb"),
               "Rails.application.routes.draw do\nend\n")
    File.write(File.join(destination_root, ".gitignore"), "/log/*\n")
  end

  test "installing is one command rather than four manual edits" do
    run_generator

    assert_file "config/initializers/masks.rb" do |written|
      assert_match(/Masks::Rails\.configure/, written)
      assert_match(/config\.issuer = ENV\.fetch\("MASKS_ISSUER"/, written)
      assert_match(/config\.after_sign_in/, written)
    end

    assert_file "config/routes.rb", %r{mount Masks::Rails::Engine, at: "/auth"}
  end

  test "the file credentials land in is gitignored, because it holds a secret" do
    run_generator

    assert_file ".gitignore", %r{/config/masks\.json}
  end

  test "a resource server gets its identifier written in rather than commented out" do
    run_generator [ "--resource", "https://app.example.com/mcp" ]

    assert_file "config/initializers/masks.rb" do |written|
      assert_match(/^  config\.resource = "https:\/\/app\.example\.com\/mcp"$/, written)
      assert_match(/^  config\.resource_scopes = \[\]$/, written)
    end
  end

  test "an app that is not a resource server is not told to pretend it is" do
    run_generator

    assert_file "config/initializers/masks.rb" do |written|
      assert_match(/# config\.resource = /, written)
      assert_no_match(/^  config\.resource = /, written)
    end
  end

  test "the mount point is where the consumer said" do
    run_generator [ "--mount", "/identity" ]

    assert_file "config/routes.rb", %r{at: "/identity"}
  end

  test "what it writes is valid ruby that configures what it claims to" do
    run_generator [ "--resource", "https://app.example.com/mcp" ]

    written = File.read(File.join(destination_root, "config/initializers/masks.rb"))

    ENV["MASKS_ISSUER"] = "https://demo.auth.test"
    eval(written) # rubocop:disable Security/Eval

    assert_equal "https://app.example.com/mcp", Masks::Rails.config.resource
    assert_equal "https://demo.auth.test", Masks::Rails.config.issuer_for(nil)
  ensure
    ENV.delete("MASKS_ISSUER")
    Masks::Rails.instance_variable_set(:@config, Masks::Rails::Configuration.new)
  end
end
