module Adapters
  class Telnyx < Sms
    field :api_key, label: "API key", secret: true
    field :from, label: "From", hint: "A Telnyx number, or a messaging profile's alphanumeric sender."

    def deliver(to:, body:)
      post_json(
        "https://api.telnyx.com/v2/messages",
        { from: sender, to: to, text: body },
        "Authorization" => "Bearer #{self[:api_key]}"
      )
    end
  end
end
