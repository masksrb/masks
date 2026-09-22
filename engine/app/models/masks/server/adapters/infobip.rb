module Masks
  module Server
    module Adapters
      class Infobip < Sms
        BASE = /\A[a-z0-9]+\.api(-[a-z0-9]+)?\.infobip\.com\z/

        field :base_url, label: "Base URL", hint: "The host Infobip gave the account, like xxxxx.api.infobip.com."
        field :api_key, label: "API key", secret: true
        field :from, label: "From"

        validate :base_is_infobip

        def deliver(to:, body:)
          post_json(
            "https://#{host}/sms/2/text/advanced",
            { messages: [ { from: sender, destinations: [ { to: to.delete_prefix("+") } ], text: body } ] },
            "Authorization" => "App #{self[:api_key]}"
          )
        end

        private

          def host
            self[:base_url].to_s.sub(%r{\Ahttps?://}, "").chomp("/")
          end

          def base_is_infobip
            errors.add(:base, "Base URL must be a host under api.infobip.com") if
              self[:base_url].present? && !host.match?(BASE)
          end
      end
    end
  end
end
