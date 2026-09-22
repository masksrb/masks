module Masks
  module Server
    require "test_helper"

    class SignInPolicyTest < ActiveSupport::TestCase
      def policy(**attributes)
        within { SignInPolicy.new({ key: "customers", name: "Customers" }.merge(attributes)) }
      end

      def valid?(held)
        within { held.valid? }
      end

      test "masks' built-in default is invitation only, asks for an email, and requires nothing more" do
        held = SignInPolicy.default

        refute held.signup
        assert held.requires?(:email)
        refute held.asks?(:phone)
        refute held.second_factor_required
        assert_equal Scopes::STANDARD, held.signup_scope_list
      end

      test "a client names its own policy, falls back to the tenant's, and then to the built-in one" do
        own = within { policy(key: "own", name: "Own").tap(&:save!) }
        tenant_wide = within { policy(key: "wide", name: "Wide").tap(&:save!) }
        client = create_client(@tenant)

        assert_equal "default", within { SignInPolicy.for(client: client).key }

        @tenant.update!(sign_in_policy: tenant_wide)
        assert_equal "wide", within { SignInPolicy.for(client: client.reload, tenant: @tenant.reload).key }

        within { client.update!(sign_in_policy: own) }
        assert_equal "own", within { SignInPolicy.for(client: client.reload, tenant: @tenant).key }

        within { own.update!(archived_at: Time.current) }
        assert_equal "wide", within { SignInPolicy.for(client: client.reload, tenant: @tenant).key }
      end

      test "signup may never grant a masks: scope" do
        held = policy(signup_scopes: "openid masks:manage")

        refute valid?(held)
        assert_includes held.errors.attribute_names, :signup_scopes
      end

      test "an account has to be named by something" do
        held = policy(nickname: "off", email: "off")

        refute valid?(held)
      end

      test "a tenant that names accounts by email cannot have a policy that does not require one" do
        @tenant.update!(named_by: Tenant::EMAIL)

        refute valid?(policy(email: "optional"))
        assert valid?(policy(email: "required"))
      end

      test "confirming by email needs an email, and so does hiding who has an account" do
        refute valid?(policy(email: "optional", confirmation: "code"))
        refute valid?(policy(email: "optional", hidden: true))
        assert valid?(policy(email: "required", confirmation: "link", hidden: true))
      end

      test "a password cannot be shorter than masks allows" do
        refute valid?(policy(password_minimum: 4))
        assert valid?(policy(password_minimum: 12))
      end

      test "a required second factor needs something other than backup codes to be offered" do
        refute valid?(policy(second_factor_required: true, second_factors: [ "backup_codes" ]))
        assert valid?(policy(second_factor_required: true, second_factors: %w[passkey backup_codes]))
      end

      test "there is always at least one way to sign in, and only ones masks knows" do
        refute valid?(policy(first_factors: []))
        refute valid?(policy(first_factors: [ "carrier-pigeon" ]))
      end

      test "email domains are kept bare and lower case, and admit only those" do
        held = policy(email_domains: [ " @Example.com ", "example.com", "other.org" ])

        assert_equal %w[example.com other.org], held.email_domains
        assert held.admits?("ada@EXAMPLE.com")
        refute held.admits?("ada@elsewhere.net")
        assert policy.admits?("anyone@anywhere.test")
      end

      test "policies are kept per tenant" do
        within { policy.save! }

        assert_equal 0, within(other_tenant) { SignInPolicy.count }
      end
    end
  end
end
