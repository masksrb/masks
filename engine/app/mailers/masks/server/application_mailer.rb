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
          return true if Current.previewing
          return Current.tenant.mails? if Current.tenant

          from.present?
        end
      end

      def mail(headers = {}, &block)
        super.tap do |message|
          adapter = Current.tenant&.mail_adapter

          if adapter
            message.delivery_method(*adapter.delivery_method)
          elsif Server.config.smtp_settings && delivery_method != :test
            message.delivery_method(:smtp, Server.config.smtp_settings)
          end
        end
      end

      private

        def deliverable?
          self.class.deliverable?
        end

        def journey!(journey)
          @journey = journey
          @tenant_name = journey.tenant_name
          @heading = journey.heading
          @signature = templates[MailTemplate::SIGNATURE]&.paragraphs_for(tenant: @tenant_name)
        end

        def customize!(kind, default:, actor: nil, **values)
          held = templates[kind.to_s]
          return default if held.nil?

          values = { tenant: @tenant_name, name: actor&.display_name, nickname: actor&.identifier }.merge(values)
          @message = held.paragraphs_for(values)

          held.subject_for(values) || default
        end

        def templates
          @templates ||= Current.tenant ? MailTemplate.all.index_by(&:kind) : {}
        end

        def home
          @journey.origin.presence && "#{@journey.origin}/"
        end
    end
  end
end
