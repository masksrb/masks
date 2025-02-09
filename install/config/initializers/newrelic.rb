Rails.configuration.after_initialize do
  if Masks.setting(:monitoring, :newrelic, :license_key)&.present?
    require "newrelic_rpm

    NewRelic::Agent.manual_start
  end
rescue ActiveRecord::StatementInvalid
  nil
end
