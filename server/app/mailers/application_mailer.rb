class ApplicationMailer < ActionMailer::Base
  layout "mailer"

  class << self
    def from
      Rails.configuration.masks.mail_from
    end

    def deliverable?
      from.present?
    end
  end

  private

    def deliverable?
      self.class.deliverable?
    end
end
