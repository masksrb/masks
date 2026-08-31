require "rails/generators/base"

module Masks
  module Generators
    class InstallGenerator < ::Rails::Generators::Base
      source_root File.expand_path("templates", __dir__)

      desc "Mount masks-rails, write an initializer, and say what to set."

      class_option :mount, type: :string, default: "/auth",
                   desc: "Where to mount the engine"
      class_option :resource, type: :string, default: nil,
                   desc: "This app's resource identifier, if it is also a resource server"

      def create_initializer
        @mount_path = options[:mount]
        @resource = options[:resource]

        template "masks.rb.tt", "config/initializers/masks.rb"
      end

      def mount_engine
        route %(mount Masks::Rails::Engine, at: "#{options[:mount]}")
      end

      def ignore_credentials
        append_to_file ".gitignore", "\n# masks: what the handshake gave this app\n/config/masks.json\n"
      end

      def say_what_is_left
        say ""
        say "masks-rails is mounted at #{options[:mount]}.", :green
        say ""
        say "  1. Set MASKS_ISSUER in the environment, or edit the initializer."
        say "  2. Start the app and open #{options[:mount]}/handshake."
        say "  3. Approve it at your masks server. The credentials land in"
        say "     config/masks.json, which the generator has gitignored."
        say ""
        say "Include Masks::Rails::Authentication in the controllers that want"
        say "it, or set config.authenticate_everything = true to have it on all"
        say "of them. Nothing is included for you."
        say ""
      end
    end
  end
end
