module Masks
  module Server
    module Adapters
      class ClickSend < Sms
        self.label = "ClickSend"

        field :username, label: "Username"
        field :api_key, label: "API key", secret: true
        field :from, label: "From", required: false

        def deliver(to:, body:)
          post_json(
            "https://rest.clicksend.com/v3/sms/send",
            { messages: [ { source: "masks", from: sender, body: body, to: to }.compact ] },
            "Authorization" => basic(self[:username], self[:api_key])
          )
        end
      end
    end
  end
end
