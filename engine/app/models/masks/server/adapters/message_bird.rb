module Masks
  module Server
    module Adapters
      class MessageBird < Sms
        self.label = "MessageBird"

        field :access_key, label: "Access key", secret: true
        field :from, label: "Originator", hint: "A number, or up to 11 letters and digits."

        def deliver(to:, body:)
          post_json(
            "https://rest.messagebird.com/messages",
            { originator: sender, recipients: [ to.delete_prefix("+") ], body: body },
            "Authorization" => "AccessKey #{self[:access_key]}"
          )
        end
      end
    end
  end
end
