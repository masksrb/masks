# frozen_string_literal: true

require 'rails/generators/active_record'

module Masks
  class InstallGenerator < Rails::Generators::Base
    include ActiveRecord::Generators::Migration

    source_root File.expand_path('templates', __dir__)

    class_option :mode,
                 type: :string,
                 desc: 'The mode to use when running masks'
    class_option :migrations, type: :string, desc: 'The path to output migrations to'

    def update_seeds
      seeds = Rails.root.join('db/seeds.rb')

      return unless File.exist?(seeds)
      return if match_file(seeds, /Masks\.seed/)

      append_file(Rails.root.join('db/seeds.rb')) do
        [
          'Masks.seed do',
          '# See https://masks.pages.dev/guides/rails',
          'end'
        ].join("\n")
      end
    end

    def mask_routes
      return if match_file(Rails.root.join('config/routes.rb'), /use_masks/)

      route "use_masks # See https://masks.pages.dev/guides/rails for more information...\n\n"
    rescue StandardError
      nil
    end

    def create_config
      @mode = options[:mode] || 'client'

      template "masks.rb.erb", Rails.root.join("config", "masks.rb")
      template "masks.yml.erb", Rails.root.join("config", "masks.yml")
    end

    def update_gemfile
      return if client_mode?(options)
      return if match_file(Rails.root.join('Gemfile'), /masks-server/)

      return unless File.exist?(Rails.root.join('Gemfile'))

      append_file(Rails.root.join('Gemfile')) { "gem 'masks-server'" }
    end

    def create_migration_file
      return unless server_mode?(options)

      migration_template 'migrations.rb.erb',
                         Rails.root.join(
                           "#{options[:migrations] || 'db/migrate'}/add_masks.rb"
                         )
    end

    private

    def client_mode?(options)
      !options[:mode] || options[:mode].to_s == 'client'
    end

    def server_mode?(options)
      %w[engine container].include?(options[:mode]&.to_s)
    end

    def migration_version
      "[#{ActiveRecord::VERSION::STRING.to_f}]"
    end
  end
end
