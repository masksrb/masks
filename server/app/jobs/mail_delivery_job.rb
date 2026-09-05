class MailDeliveryJob < ActionMailer::MailDeliveryJob
  include TenantAware
end
