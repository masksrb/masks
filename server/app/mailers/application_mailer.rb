class ApplicationMailer < ActionMailer::Base
  layout "mailer"

  class << self
    def from
      Current.tenant&.mail_from || Rails.configuration.masks.mail_from
    end

    def deliverable?
      return Current.tenant.mails? if Current.tenant

      from.present?
    end
  end

  def mail(headers = {}, &block)
    super.tap do |message|
      held = Current.tenant

      message.delivery_method(:smtp, held.smtp_settings) if held&.own_smtp?
    end
  end

  private

    def deliverable?
      self.class.deliverable?
    end
end
