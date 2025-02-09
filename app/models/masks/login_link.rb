module Masks
  class LoginLink < ApplicationRecord
    self.table_name = "masks_login_links"

    include Masks::Settings

    serialize :settings, coder: JSON

    setting :url, :string

    scope :active,
          -> { where("revoked_at IS NULL AND expires_at > ?", Time.now.utc) }

    scope :for_verification, -> { where(log_in: false) }

    scope :for_login, -> { where(log_in: true) }

    belongs_to :client, class_name: "Masks::Client"
    belongs_to :email, class_name: "Masks::Email"
    belongs_to :actor, class_name: Masks.conf.actor_model
    belongs_to :device, class_name: "Masks::Device"

    after_initialize :set_defaults

    validates :url, presence: true
    validates :code,
              presence: true,
              uniqueness: {
                scope: %i[email_id device_id client_id],
              }
    validates :expires_at, :origin_url, :accept_url, presence: true

    def chars
      code.length
    end

    def deliverable?
      valid?
    end

    def save_and_deliver
      return unless save

      mailer = LoginLinkMailer.with(login_link: self)

      begin
        log_in? ? mailer.authenticate.deliver_now : mailer.verify.deliver_now
      rescue => e
        if log_in?
          mailer.authenticate.deliver_later
        else
          mailer.verify.deliver_later
        end
      end
    end

    def authenticated!
      return if authenticated?

      touch(:authenticated_at)

      verified!
    end

    def verified!
      email.verify!

      touch(:revoked_at)

      true
    end

    def authenticated?
      authenticated_at.present?
    end

    def reset_password(password)
      return unless !reset_password_at

      actor.password = password
      saved = actor.save

      touch(:reset_password_at) if saved

      saved
    end

    def active?
      !revoked?
    end

    def revoked?
      revoked_at&.present? || (expires_at && expires_at < Time.now.utc)
    end

    def email=(email)
      self.actor ||= email&.actor

      super email
    end

    def accept_url
      origin_url(login_code: code)
    end

    def origin_url(**extras)
      return unless url

      uri = Addressable::URI.parse(url)
      uri.query_values = (uri.query_values || {}).merge(extras)
      uri.to_s
    end

    def set_defaults
      self.code ||= SecureRandom.base36(7).upcase
      self.expires_at ||= client&.expires_at(:login_link)
    end
  end
end
