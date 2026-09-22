module Masks
  module Server
    class MailDeliveryJob < ActionMailer::MailDeliveryJob
      include Tenancy::Job
    end
  end
end
