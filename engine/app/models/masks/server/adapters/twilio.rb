module Masks
  module Server
    module Adapters
      class Twilio < Sms
        field :account_sid, label: "Account SID"
        field :auth_token, label: "Auth token", secret: true
        field :from, label: "From", hint: "A Twilio number like +15551234567, or a Messaging Service SID."

        def deliver(to:, body:)
          sender_field = sender.to_s.start_with?("MG") ? "MessagingServiceSid" : "From"

          post_form(
            "https://api.twilio.com/2010-04-01/Accounts/#{ERB::Util.url_encode(self[:account_sid])}/Messages.json",
            { "To" => to, sender_field => sender, "Body" => body },
            "Authorization" => basic(self[:account_sid], self[:auth_token])
          )
        end
      end
    end
  end
end
