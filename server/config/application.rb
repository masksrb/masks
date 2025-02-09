require_relative "boot"

require "rails/all"

Bundler.require(*Rails.groups)

module Server
  class Application < Rails::Application
    config.load_defaults Rails::VERSION::STRING.to_f

    # For compatibility with applications that use this config
    config.action_controller.include_all_helpers = false

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")
    config.active_storage.service = "masks"
    config.to_prepare { Masks.reset! }

    # The mailer shim allows dynamic reconfiguration on the server
    config.action_mailer.delivery_method = Masks::Shims::ActionMailer

    SolidQueue.logger = ActiveSupport::Logger.new(STDOUT)

    initializer "masks.workers" do
      next if Rails.env.test? || !Masks.mode.server?

      config.active_job.queue_adapter = :solid_queue

      if Masks.conf.db.enabled?(:queue)
        config.solid_queue.connects_to = { database: { writing: :queue } }
      end

      config.cache_store = :solid_cache_store
    end

    # Auth is managed by masks
    config.mission_control.jobs.http_basic_auth_enabled = false
  end
end
