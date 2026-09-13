require "test_helper"

class SmsAdaptersTest < ActiveSupport::TestCase
  TO = "+15557654321".freeze

  def adapter(klass, **config)
    within { klass.new(key: klass.service.tr("_", "-"), name: klass.label).configure(config) }
  end

  def deliver(held)
    within { held.deliver(to: TO, body: "Your code is 123456") }
  end

  test "a number is kept only in international form" do
    assert_equal "+15551234567", Adapters::Sms.number("+1 (555) 123-4567")
    assert_nil Adapters::Sms.number("555 123 4567")
    assert_nil Adapters::Sms.number("+0123456789")
  end

  test "twilio posts a form with basic auth, and a messaging service by its sid" do
    stub = stub_request(:post, "https://api.twilio.com/2010-04-01/Accounts/AC123/Messages.json")
           .with(basic_auth: %w[AC123 token],
                 body: { "To" => TO, "From" => "+15551234567", "Body" => "Your code is 123456" })
           .to_return(status: 201, body: "{}")

    deliver(adapter(Adapters::Twilio, account_sid: "AC123", auth_token: "token", from: "+15551234567"))

    assert_requested stub

    service = stub_request(:post, "https://api.twilio.com/2010-04-01/Accounts/AC123/Messages.json")
              .with(body: hash_including("MessagingServiceSid" => "MG999"))
              .to_return(status: 201, body: "{}")

    deliver(adapter(Adapters::Twilio, account_sid: "AC123", auth_token: "token", from: "MG999"))

    assert_requested service
  end

  test "a refusal is raised with what the service said" do
    stub_request(:post, %r{api.twilio.com}).to_return(status: 401, body: %({"message":"Authenticate"}))

    failure = assert_raises(Adapter::Failed) do
      deliver(adapter(Adapters::Twilio, account_sid: "AC123", auth_token: "wrong", from: "+15551234567"))
    end

    assert_match "401", failure.message
    assert_match "Authenticate", failure.message
  end

  test "vonage reads its status out of a successful response" do
    stub_request(:post, "https://rest.nexmo.com/sms/json")
      .with(body: hash_including("api_key" => "key", "to" => "15557654321", "from" => "masks"))
      .to_return(status: 200, body: { messages: [ { status: "4", "error-text": "Bad Credentials" } ] }.to_json)

    failure = assert_raises(Adapter::Failed) do
      deliver(adapter(Adapters::Vonage, api_key: "key", api_secret: "secret", from: "masks"))
    end

    assert_match "Bad Credentials", failure.message
  end

  test "plivo, telnyx, sinch, messagebird, infobip and clicksend each reach their own endpoint" do
    cases = {
      Adapters::Plivo => [ "https://api.plivo.com/v1/Account/MA1/Message/",
                           { auth_id: "MA1", auth_token: "t", from: "+15551234567" },
                           { "Authorization" => "Basic #{Base64.strict_encode64('MA1:t')}" },
                           { "src" => "+15551234567", "dst" => TO } ],
      Adapters::Telnyx => [ "https://api.telnyx.com/v2/messages",
                            { api_key: "KEY", from: "+15551234567" },
                            { "Authorization" => "Bearer KEY" },
                            { "from" => "+15551234567", "to" => TO } ],
      Adapters::Sinch => [ "https://eu.sms.api.sinch.com/xms/v1/plan/batches",
                           { service_plan_id: "plan", api_token: "T", region: "eu", from: "+15551234567" },
                           { "Authorization" => "Bearer T" },
                           { "to" => [ TO ] } ],
      Adapters::MessageBird => [ "https://rest.messagebird.com/messages",
                                 { access_key: "AK", from: "masks" },
                                 { "Authorization" => "AccessKey AK" },
                                 { "recipients" => [ "15557654321" ] } ],
      Adapters::Infobip => [ "https://abc123.api.infobip.com/sms/2/text/advanced",
                             { base_url: "https://abc123.api.infobip.com/", api_key: "IB", from: "masks" },
                             { "Authorization" => "App IB" },
                             {} ],
      Adapters::ClickSend => [ "https://rest.clicksend.com/v3/sms/send",
                               { username: "u", api_key: "k" },
                               { "Authorization" => "Basic #{Base64.strict_encode64('u:k')}" },
                               {} ]
    }

    cases.each do |klass, (url, config, headers, body)|
      held = adapter(klass, **config)

      assert within { held.valid? }, "#{klass.label}: #{held.errors.full_messages.join(', ')}"

      stub = stub_request(:post, url).with(headers: headers, body: hash_including(body)).to_return(status: 200, body: "{}")

      deliver(held)

      assert_requested stub
    end
  end

  test "infobip refuses a base url that is not infobip's" do
    held = adapter(Adapters::Infobip, base_url: "evil.example.com", api_key: "IB", from: "masks")

    refute within { held.valid? }
  end

  test "sns signs a publish with signature version 4" do
    stub = stub_request(:post, "https://sns.eu-west-1.amazonaws.com/")
           .with { |request|
             request.headers["Authorization"].to_s.match?(
               %r{\AAWS4-HMAC-SHA256 Credential=AKIA1/\d{8}/eu-west-1/sns/aws4_request, SignedHeaders=content-type;host;x-amz-date, Signature=\h{64}\z}
             ) && request.body.include?("Action=Publish") && request.body.include?("PhoneNumber=%2B15557654321")
           }
           .to_return(status: 200, body: "<PublishResponse/>")

    deliver(adapter(Adapters::Sns, access_key_id: "AKIA1", secret_access_key: "s", region: "eu-west-1"))

    assert_requested stub
  end

  test "sns refuses a region that is not a region" do
    refute within { adapter(Adapters::Sns, access_key_id: "A", secret_access_key: "s", region: "moon").valid? }
  end

  test "a required field left blank is refused, and a secret is never in the settings" do
    held = adapter(Adapters::Twilio, account_sid: "AC123", from: "+15551234567")

    refute within { held.valid? }
    assert_match "Auth token", held.errors.full_messages.join

    held.configure(auth_token: "token")

    assert within { held.valid? }
    refute held.public_settings.key?("auth_token")
  end

  test "a test message needs a number in international form" do
    held = adapter(Adapters::SmsLog)

    assert_raises(Adapter::Failed) { within { held.deliver_test("555") } }

    within { held.deliver_test("+15557654321") }

    assert_equal "+15557654321", Adapters::SmsLog.deliveries.last[:to]
  end
end
