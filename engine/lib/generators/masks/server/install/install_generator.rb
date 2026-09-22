require "rails/generators/base"

module Masks
  module Server
    module Generators
      class InstallGenerator < ::Rails::Generators::Base
        source_root File.expand_path("templates", __dir__)

        desc "Mount the masks provider in this app, write its initializer, and say what the database needs."

        class_option :mode, type: :string, default: "engine", enum: %w[engine server],
                     desc: "engine mounts masks inside this app; server makes this app masks and nothing else"
        class_option :at, type: :string, default: "/auth",
                     desc: "The path to mount masks at, in engine mode"
        class_option :host, type: :string, default: nil,
                     desc: "A subdomain to serve masks on instead of a path, in engine mode"
        class_option :database, type: :string, default: "masks",
                     desc: "The database.yml entry masks keeps its tables in, in engine mode"
        class_option :tenant, type: :string, default: "app",
                     desc: "The tenant this app's accounts belong to, in engine mode"

        def create_initializer
          template "masks_server.rb.tt", "config/initializers/masks_server.rb"
        end

        def mount_engine
          route mount_line
        end

        def say_what_is_left
          say ""
          say "masks is mounted #{where}.", :green
          say ""

          engine? ? say_engine_database : say_server_database

          say "In production, set MASKS_PUBLIC_ORIGIN_TEMPLATE to #{origin_example}, so the issuer and every"
          say "emailed link are built from it and never from a request's Host header."
          say ""
          say "Then run bin/rails db:prepare and bin/rails masks:tenants, and open #{login_path} to set up"
          say "the first account with the setup token masks prints."
          say ""
        end

        private

          def engine?
            options[:mode] == "engine"
          end

          def subdomain?
            engine? && options[:host].present?
          end

          def mount_path
            engine? && !subdomain? ? options[:at] : "/"
          end

          def mount_line
            mount = %(mount Masks::Server::Engine, at: "#{mount_path}")

            subdomain? ? %(constraints(host: "#{options[:host]}") { #{mount} }) : mount
          end

          def where
            return "at the root of #{options[:host]}" if subdomain?

            "at #{mount_path}"
          end

          def login_path
            mount_path == "/" ? "/login" : "#{mount_path}/login"
          end

          def origin_example
            return "https://#{options[:host]}" if subdomain?
            return "https://auth.example.com" unless engine?

            "https://app.example.com#{options[:at]}"
          end

          def say_engine_database
            say "Add a database of its own for masks to config/database.yml, in each environment:"
            say ""
            say "  #{options[:database]}:"
            say "    <<: *default"
            say "    database: #{File.basename(destination_root)}_#{options[:database]}_<%= Rails.env %>"
            say "    username: masks"
            say "    migrations_paths: <%= Masks::Server::Engine.root.join(\"db/migrate\") %>"
            say "    schema_dump: false"
            say ""
            say "Its role must hold neither SUPERUSER nor BYPASSRLS, or masks refuses to start: row-level"
            say "security is what keeps one tenant's accounts and keys away from another's."
            say ""
            say "Controllers that need the signed-in account include Masks::Server::Host, which gives them"
            say "masks_actor and require_masks_actor!." unless subdomain?
            say "On a subdomain, sign this app in with the masks gem's Masks::Rails, as any other client." if subdomain?
            say ""
          end

          def say_server_database
            say "masks keeps its tables in the primary database. Connect as a role holding neither"
            say "SUPERUSER nor BYPASSRLS, and set config.active_record.schema_format = :sql, since"
            say "row-level security does not survive a schema.rb."
            say ""
          end
      end
    end
  end
end
