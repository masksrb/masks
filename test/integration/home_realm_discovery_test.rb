module Masks
  module Server
    require "test_helper"

    class HomeRealmDiscoveryTest < ActionDispatch::IntegrationTest
      include Federated

      setup do
        create_actor(nickname: "owner", email: "owner@elsewhere.example")
        @provider = create_provider(role: "delegate", email_domains: "acme.test")
        @claim = within { DomainClaim.create!(domain: "acme.test", provider: @provider) }
      end

      def answering(lookup)
        held = DomainClaim.method(:txt_records)
        DomainClaim.define_singleton_method(:txt_records) { |name| lookup.call(name) }

        yield
      ensure
        DomainClaim.define_singleton_method(:txt_records, held)
      end

      def publish(claim, value = claim.record_value, &block)
        answering(->(name) { name == claim.record_name ? [ value ] : [] }, &block)
      end

      def identify(identifier)
        post "/login", params: { event: "identify", identifier: identifier }, as: :json

        JSON.parse(response.body)
      end

      test "an address at a proven domain goes straight to its provider" do
        within { publish(@claim) { @claim.check! } }

        body = identify("grace@acme.test")

        assert_match @upstream.url("/o/authorize"), body["redirectTo"].to_s
      end

      test "an unproven claim sends nobody anywhere" do
        body = identify("grace@acme.test")

        assert_nil body["redirectTo"]
      end

      test "an address elsewhere, or a nickname, signs in the usual way" do
        within { publish(@claim) { @claim.check! } }

        assert_nil identify("grace@globex.test")["redirectTo"]
        assert_nil identify("grace")["redirectTo"]
      end

      test "a person routed to the provider finishes signing in through it" do
        within { publish(@claim) { @claim.check! } }

        handoff = identify("grace@acme.test")
        state = Rack::Utils.parse_query(URI.parse(handoff["redirectTo"]).query)["state"]
        nonce = Rack::Utils.parse_query(URI.parse(handoff["redirectTo"]).query)["nonce"]

        finish_sso(sub: "upstream-9", email: "grace@acme.test", handoff: { "state" => state, "nonce" => nonce })

        assert_equal "grace@acme.test", signed_in_actor&.email, refusals.join("; ")
      end

      test "a claim needs the exact record, and another tenant cannot prove the same domain" do
        within { publish(@claim, "masks-verification=wrong") { refute @claim.check! } }
        within { publish(@claim) { assert @claim.check! } }

        other = other_tenant
        rival = Tenant.switch(other) { DomainClaim.create!(domain: "acme.test") }

        Tenant.switch(other) do
          publish(rival) { assert_raises(DomainClaim::Taken) { rival.check! } }
        end
      end

      test "a proven domain whose record disappears is released after a week" do
        within do
          publish(@claim) { @claim.check! }

          answering(->(_name) { [] }) do
            @claim.check!
            assert @claim.verified?

            travel(DomainClaim::GRACE + 1.hour) { @claim.check! }
          end

          refute @claim.reload.verified?
        end
      end

      test "the hourly check proves claims in every tenant and records it" do
        answering(->(_name) { [ @claim.record_value ] }) do
          CheckDomainClaimsJob.perform_now
        end

        within do
          assert @claim.reload.verified?
          assert Event.exists?(action: Event::DOMAIN_VERIFIED)
        end
      end
    end
  end
end
