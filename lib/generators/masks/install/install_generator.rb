# frozen_string_literal: true
require "rails/generators/active_record"

class Masks::InstallGenerator < Rails::Generators::Base
  include ActiveRecord::Generators::Migration

  source_root File.expand_path("templates", __dir__)

  class_option :url, type: :string, desc: "The url to the masks server"
  class_option :server,
               type: :boolean,
               desc: "Host the masks server (in additional to the client)"
  class_option :migrations, type: :boolean, desc: "Only generate migrations"
  class_option :database,
               type: :string,
               aliases: %i[--db],
               desc:
                 "The database for your migration. By default, the current environment's primary database is used."

  def update_seeds
    return if options[:migrations] || !options[:server]
    return if match_file(Rails.root.join("db/seeds.rb"), /Masks\.seed/)

    append_file(Rails.root.join("db/seeds.rb")) do
      [
        "Masks.seed do",
        "  # See https://masksrb.github.io/guides/rails",
        "end",
      ].join("\n")
    end
  end

  def mask_routes
    return if options[:migrations]
    return if match_file(Rails.root.join("config/routes.rb"), /use_masks/)

    route "use_masks # See https://masksrb.github.io/guides/rails for more information...\n\n"
  rescue => e
    nil
  end

  def update_gemfile
    return unless options[:server]
    return if match_file(Rails.root.join("Gemfile"), /masks-server/)

    append_file(Rails.root.join("Gemfile")) { "gem 'masks-server'" }
  end

  def create_yml_files
    return if options[:migrations]

    @url = options[:url]
    @server = options[:server]

    template "masks.yml.erb", Rails.root.join("config", "masks.yml")
    template "clients.yml.erb", Rails.root.join("config", "clients.yml")

    if options[:server]
      template "providers.yml.erb", Rails.root.join("config", "providers.yml")
      template "actors.yml.erb", Rails.root.join("config", "actors.yml")
    end
  end

  def create_migration_file
    if options[:server] || options[:migrations]
      migration_template "migrations.rb.erb",
                         Rails.root.join(
                           "db/#{options[:database] || "migrate"}/add_masks.rb",
                         )
    end
  end

  private

  def migration_version
    "[#{ActiveRecord::VERSION::STRING.to_f}]"
  end
end
