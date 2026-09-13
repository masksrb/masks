module Adapters
  class Sns < Sms
    SERVICE = "sns".freeze
    VERSION = "2010-03-31".freeze
    REGION = /\A[a-z]{2}(-[a-z]+)+-\d\z/

    self.label = "Amazon SNS"

    field :access_key_id, label: "Access key ID"
    field :secret_access_key, label: "Secret access key", secret: true
    field :region, label: "Region", default: "us-east-1"
    field :from, label: "Sender ID", required: false, hint: "Honoured only where the destination allows one."

    validate :region_is_a_region

    def deliver(to:, body:)
      form = { "Action" => "Publish", "Version" => VERSION, "PhoneNumber" => to, "Message" => body }

      if sender.present?
        form["MessageAttributes.entry.1.Name"] = "AWS.SNS.SMS.SenderID"
        form["MessageAttributes.entry.1.Value.DataType"] = "String"
        form["MessageAttributes.entry.1.Value.StringValue"] = sender
      end

      payload = URI.encode_www_form(form)

      post_form(endpoint, form, signed(payload))
    end

    private

      def endpoint
        "https://#{host}/"
      end

      def host
        "sns.#{self[:region]}.amazonaws.com"
      end

      def signed(payload, now = Time.now.utc)
        stamp = now.strftime("%Y%m%dT%H%M%SZ")
        date = now.strftime("%Y%m%d")
        scope = "#{date}/#{self[:region]}/#{SERVICE}/aws4_request"
        content_type = "application/x-www-form-urlencoded"
        digest = OpenSSL::Digest::SHA256.hexdigest(payload)

        headers = { "content-type" => content_type, "host" => host, "x-amz-date" => stamp }
        names = headers.keys.sort.join(";")
        canonical = [
          "POST", "/", "",
          headers.sort.map { |name, value| "#{name}:#{value}\n" }.join,
          names, digest
        ].join("\n")

        to_sign = [ "AWS4-HMAC-SHA256", stamp, scope, OpenSSL::Digest::SHA256.hexdigest(canonical) ].join("\n")

        key = [ date, self[:region], SERVICE, "aws4_request" ].reduce("AWS4#{self[:secret_access_key]}") do |held, part|
          OpenSSL::HMAC.digest("SHA256", held, part)
        end

        {
          "X-Amz-Date" => stamp,
          "Authorization" => "AWS4-HMAC-SHA256 Credential=#{self[:access_key_id]}/#{scope}, " \
                             "SignedHeaders=#{names}, Signature=#{OpenSSL::HMAC.hexdigest('SHA256', key, to_sign)}"
        }
      end

      def region_is_a_region
        errors.add(:base, "Region must look like us-east-1") if self[:region].present? && !self[:region].match?(REGION)
      end
  end
end
