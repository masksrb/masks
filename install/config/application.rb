require_relative "boot"

require "rails/all"

Bundler.require(*Rails.groups)

module Install
  class Application < Rails::Application
    config.load_defaults Rails::VERSION::STRING.to_f

    Masks::Engine.use_secrets(config)
    Masks::Engine.use_sessions(config)

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
    config.action_mailer.delivery_method = Masks::Shims::ActionMailer

    SolidQueue.logger = ActiveSupport::Logger.new(STDOUT)

    unless Rails.env.test?
      config.active_job.queue_adapter = :solid_queue

      if Masks.env.db_enabled?(:queue)
        config.solid_queue.connects_to = { database: { writing: :queue } }
      end

      config.cache_store = :solid_cache_store
    end
  end
end
