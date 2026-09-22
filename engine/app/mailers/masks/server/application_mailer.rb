module Masks
  module Server
    class ApplicationMailer < ActionMailer::Base
      layout "masks/server/mailer"
      helper ApplicationHelper

      self.delivery_job = MailDeliveryJob

      class << self
        def from
          Current.tenant&.mail_from || ::Rails.configuration.masks.mail_from
        end

        def deliverable?
          return Current.tenant.mails? if Current.tenant

          from.present?
        end
      end

      def mail(headers = {}, &block)
        super.tap do |message|
          adapter = Current.tenant&.mail_adapter

          message.delivery_method(*adapter.delivery_method) if adapter
        end
      end

      private

        def deliverable?
          self.class.deliverable?
        end
    end
  end
end
