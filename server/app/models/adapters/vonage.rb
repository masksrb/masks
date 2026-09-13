module Adapters
  class Vonage < Sms
    field :api_key, label: "API key"
    field :api_secret, label: "API secret", secret: true
    field :from, label: "From", hint: "A number or an alphanumeric sender ID."

    def deliver(to:, body:)
      response = post_form(
        "https://rest.nexmo.com/sms/json",
        { "api_key" => self[:api_key], "api_secret" => self[:api_secret],
          "from" => sender.delete_prefix("+"), "to" => to.delete_prefix("+"), "text" => body }
      )

      held = Array(parsed(response)["messages"]).first || {}

      raise Failed, "Vonage refused the message: #{held['error-text'] || 'no status'}" unless held["status"] == "0"

      response
    end
  end
end
