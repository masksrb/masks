module Masks
  module Server
    require "test_helper"
    require_relative "../support/fake_authenticator"

    class EnrolmentTest < ActionDispatch::IntegrationTest
      setup do
        host! host_for(@tenant)

        @manager = create_actor(@tenant, nickname: "boss", scopes: "openid masks:manage", otp: false)
        @device = FakeAuthenticator.new(origin_for(@tenant))
      end

      def event(name, **params)
        post "/login", params: { event: name, **params }, as: :json
        JSON.parse(response.body)
      end

      def add_passkey(user_verified: true)
        offer = event("enrol:passkey-challenge")
        credential = @device.enrol(offer.dig("enrolment", "passkeys", "options"), user_verified: user_verified)

        event("enrol:passkey", passkey: JSON.generate(credential))
      end

      def factored
        within(@tenant) { @manager.reload }
      end

      test "a manager with no second factor is stopped at sign-in until one is added" do
        body = sign_in_as(@manager)

        assert_equal "enrol", body["prompt"]
        assert body.dig("enrolment", "required")

        body = event("enrol:done", kept: "1")

        assert_equal "enrol", body["prompt"]
        assert_includes body["warnings"], "second-factor-required"
        assert_nil within(@tenant) { Session.live.find_by(actor_id: @manager.id) }
      end

      test "a person who does not manage anything is not asked" do
        reader = create_actor(@tenant, nickname: "reader")

        assert_equal "settled", sign_in_as(reader)["prompt"]
      end

      test "a wrong code turns nothing on" do
        sign_in_as(@manager)

        body = event("enrol:otp", code: "000000")

        assert_includes body["warnings"], "invalid-code"
        refute factored.otp?
      end

      test "an authenticator app, then backup codes that must be kept, then signed in" do
        body = sign_in_as(@manager)
        secret = body.dig("enrolment", "otp", "secret").delete(" ")

        body = event("enrol:otp", code: ROTP::TOTP.new(secret).now)

        assert factored.otp?
        assert_equal "enrol", body["prompt"], "the screen stays open for more factors"
        assert_equal Actor::BACKUP_CODES, body.dig("enrolment", "backupCodes", "issued").length

        body = event("enrol:done")

        assert_includes body["warnings"], "backup-codes-unkept"

        body = event("enrol:done", kept: "1")

        assert body["settled"]
        assert_includes within(@tenant) { Session.live.find_by(actor_id: @manager.id).amr }, "mfa"
      end

      test "issued backup codes can be downloaded as a file, without a request of their own" do
        body = sign_in_as(@manager)
        secret = body.dig("enrolment", "otp", "secret").delete(" ")
        issued = event("enrol:otp", code: ROTP::TOTP.new(secret).now).dig("enrolment", "backupCodes", "issued")

        get "/login"

        assert_select "a[download^='backup-codes-']" do |links|
          saved = CGI.unescape(links.first["href"].delete_prefix("data:text/plain;charset=utf-8,"))

          assert_equal issued, saved.lines.map(&:strip).last(issued.length)
          assert_includes saved, @manager.identifier
        end
      end

      test "an authenticator already on cannot be replaced through enrolment" do
        body = sign_in_as(@manager)
        secret = body.dig("enrolment", "otp", "secret").delete(" ")
        event("enrol:otp", code: ROTP::TOTP.new(secret).now)
        held = factored.otp_secret

        event("enrol:otp", code: ROTP::TOTP.new(ROTP::Base32.random).now)

        assert_equal held, factored.otp_secret
      end

      test "a passkey counts, and as many can be added as are wanted" do
        sign_in_as(@manager)

        body = add_passkey

        assert within(@tenant) { factored.verified_passkeys? }
        refute body.dig("enrolment", "required")
        assert_equal Actor::BACKUP_CODES, body.dig("enrolment", "backupCodes", "issued").length

        add_passkey

        assert_equal 2, within(@tenant) { factored.passkeys.count }
        assert event("enrol:done", kept: "1")["settled"]
      end

      test "first-run setup can ask for a passkey without the session cookie overflowing" do
        within(@tenant) { Actor.delete_all }

        post "/login", params: { event: "signup", token: @tenant.setup_token!, name: "Ada Lovelace",
                                 nickname: "admin-with-a-long-nickname",
                                 email: "a-rather-long-address@a-long-domain.example.com",
                                 password: "a-long-enough-password", password_confirmation: "a-long-enough-password" },
             as: :json

        assert_equal "enrol", JSON.parse(response.body)["prompt"]

        offer = event("enrol:passkey-challenge")

        assert_response :success
        assert offer.dig("enrolment", "passkeys", "options", "challenge")
        assert_operator cookies.to_hash.values.sum(&:bytesize), :<, 3500
      end

      test "a passkey that does not verify the person is refused" do
        sign_in_as(@manager)

        body = add_passkey(user_verified: false)

        assert_includes body["warnings"], "passkey-unverified"
        refute within(@tenant) { factored.second_factor? }
      end

      test "a manager with only a passkey is asked for it after a password" do
        sign_in_as(@manager)
        add_passkey
        event("enrol:done", kept: "1")
        reset!
        host! host_for(@tenant)

        body = sign_in_as(@manager)

        assert_equal "second-factor", body["prompt"]
        assert_equal({ "otp" => false, "passkey" => true, "email" => false, "sms" => false }, body["secondFactors"])

        offer = event("passkey:challenge")
        credential = @device.assert(offer.dig("passkey", "options"))

        assert event("passkey:verify", passkey: JSON.generate(credential))["settled"]
      end
    end
  end
end
