# frozen_string_literal: true
require "rails/generators/active_record"

class Masks::InstallGenerator < Rails::Generators::Base
  include ActiveRecord::Generators::Migration

  source_root File.expand_path("templates", __dir__)

  class_option :database,
               type: :string,
               aliases: %i[--db],
               desc:
                 "The database for your migration. By default, the current environment's primary database is used."
  class_option :migrations_only,
               type: :boolean,
               desc: "Only generate migrations"

  def update_seeds
    return if options[:migrations_only]
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
    return if options[:migrations_only]
    route "use_masks # See https://masksrb.github.io/guides/rails for more information..."
  rescue => e
    nil
  end

  def create_yml_files
    return if options[:migrations_only]
    template "masks.yml.erb", Rails.root.join("config", "masks.yml")
    template "clients.yml.erb", Rails.root.join("config", "clients.yml")
    template "providers.yml.erb", Rails.root.join("config", "providers.yml")
    template "actors.yml.erb", Rails.root.join("config", "actors.yml")
  end

  def create_migration_file
    migration_template "migrations.rb.erb",
                       Rails.root.join(
                         "db/#{options[:database] || "migrate"}/add_masks.rb",
                       )
  end

  private

  def migration_version
    "[#{ActiveRecord::VERSION::STRING.to_f}]"
  end
end
