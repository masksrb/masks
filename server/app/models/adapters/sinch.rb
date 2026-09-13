module Adapters
  class Sinch < Sms
    REGIONS = %w[us eu au br ca].freeze

    field :service_plan_id, label: "Service plan ID"
    field :api_token, label: "API token", secret: true
    field :region, label: "Region", options: REGIONS, default: "us"
    field :from, label: "From"

    def deliver(to:, body:)
      post_json(
        "https://#{self[:region]}.sms.api.sinch.com/xms/v1/#{ERB::Util.url_encode(self[:service_plan_id])}/batches",
        { from: sender, to: [ to ], body: body },
        "Authorization" => "Bearer #{self[:api_token]}"
      )
    end
  end
end
