module Masks
  module Server
    module Adapters
      class Plivo < Sms
        field :auth_id, label: "Auth ID"
        field :auth_token, label: "Auth token", secret: true
        field :from, label: "From"

        def deliver(to:, body:)
          post_json(
            "https://api.plivo.com/v1/Account/#{ERB::Util.url_encode(self[:auth_id])}/Message/",
            { src: sender, dst: to, text: body },
            "Authorization" => basic(self[:auth_id], self[:auth_token])
          )
        end
      end
    end
  end
end
