module Masks
  module Adapters
    class SmtpAdapter
      include Masks::Adapter

      setting :address, :string, env: "MASKS_SMTP_ADDRESS"
      setting :port, :string, env: "MASKS_SMTP_PORT"
      setting :domain, :string, env: "MASKS_SMTP_DOMAIN"
      setting :user_name, :string, env: "MASKS_SMTP_USER_NAME"
      setting :password, :string, env: "MASKS_SMTP_PASSWORD"
      setting :authentication, :string, env: "MASKS_SMTP_AUTHENTICATION"

      def default_name
        "SMTP"
      end

      def setup?
        address
      end

      def to_mailer
        Mail::SMTP.new(settings.symbolize_keys.compact)
      end
    end
  end
end
