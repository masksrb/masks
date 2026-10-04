module Masks
  module Server
    module Adapters
      class Smtp < Mail
        AUTHENTICATIONS = %w[plain login cram_md5].freeze
        TIMEOUT = 10
        UNREACHABLE = "Server resolves to an address this server will not call".freeze

        self.label = "SMTP"

        field :address, label: "Server", hint: "smtp.example.com"
        field :port, label: "Port", type: :integer, default: 587
        field :username, label: "Username", required: false
        field :password, label: "Password", secret: true, required: false
        field :authentication, label: "Authentication", options: AUTHENTICATIONS, default: "plain"
        field :domain, label: "HELO domain", required: false
        field :tls, label: "Implicit TLS", type: :boolean, default: false,
                    hint: "Off means STARTTLS, which is what port 587 expects."

        validate :port_is_a_port
        validate :address_is_public

        def delivery_method
          raise Failed, UNREACHABLE unless public?

          [
            :smtp,
            {
              address: self[:address],
              port: self[:port],
              user_name: self[:username],
              password: self[:password],
              authentication: self[:authentication].to_sym,
              domain: self[:domain],
              tls: self[:tls],
              enable_starttls: !self[:tls],
              openssl_verify_mode: OpenSSL::SSL::VERIFY_PEER,
              open_timeout: TIMEOUT,
              read_timeout: TIMEOUT
            }.compact
          ]
        end

        private

          def public?
            ::Rails.env.local? || Outbound.public_address(self[:address], self[:port].to_i).present?
          end

          def address_is_public
            errors.add(:base, UNREACHABLE) if self[:address].present? && !public?
          end

          def port_is_a_port
            errors.add(:base, "Port must be between 1 and 65535") unless (1..65_535).cover?(self[:port].to_i)
          end
      end
    end
  end
end
