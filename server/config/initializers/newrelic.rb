Rails.configuration.after_initialize do
  if Masks.conf.newrelic_license_key
    require "newrelic_rpm"

    NewRelic::Agent.manual_start
  end
rescue ActiveRecord::StatementInvalid
  nil
rescue => e
  Rails.logger.warn("Failed to configure new relic: #{e}")
end
