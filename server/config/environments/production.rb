require "active_support/core_ext/integer/time"

Rails.application.configure do
  config.enable_reloading = false

  config.eager_load = true

  config.consider_all_requests_local = false

  config.action_controller.perform_caching = true

  config.public_file_server.headers = { "cache-control" => "public, max-age=#{1.year.to_i}" }

  config.assume_ssl = ENV.fetch("RAILS_ASSUME_SSL", "true") == "true"

  config.force_ssl = ENV.fetch("RAILS_FORCE_SSL", "true") == "true"

  config.log_tags = [ :request_id ]
  config.logger   = ActiveSupport::TaggedLogging.logger(STDOUT)

  config.log_level = ENV.fetch("RAILS_LOG_LEVEL", "info")

  config.silence_healthcheck_path = "/up"

  config.active_support.report_deprecations = false

  config.cache_store = :solid_cache_store

  config.active_job.queue_adapter = :solid_queue
  config.solid_queue.connects_to = { database: { writing: :queue } }

  config.active_record.dump_schema_after_migration = false

  config.active_record.attributes_for_inspect = [ :id ]

  template = config.masks.public_origin_template

  if template.present?
    served =
      begin
        URI.parse(format(template, subdomain: "tenant")).host
      rescue ArgumentError, KeyError, URI::InvalidURIError
        nil
      end

    if served.blank?
      raise "MASKS_PUBLIC_ORIGIN_TEMPLATE must be an absolute origin with a scheme, " \
            "such as https://%{subdomain}.auth.example.com — got #{template.inspect}"
    end

    config.hosts << (template.include?("%{subdomain}") ? ".#{served.split('.', 2).last}" : served)
  end

  config.host_authorization = { exclude: ->(request) { request.path == "/up" } }
end
