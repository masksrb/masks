require "test_helper"

class SingleTenantTest < ActionDispatch::IntegrationTest
  def with_pinned(subdomain, declared: [])
    was_tenant = Rails.configuration.masks.tenant
    was_tenants = Rails.configuration.masks.tenants

    Rails.configuration.masks.tenant = subdomain
    Rails.configuration.masks.tenants = declared

    yield
  ensure
    Rails.configuration.masks.tenant = was_tenant
    Rails.configuration.masks.tenants = was_tenants
  end

  def with_origin(origin)
    was = Rails.configuration.masks.public_origin_template
    Rails.configuration.masks.public_origin_template = origin

    yield
  ensure
    Rails.configuration.masks.public_origin_template = was
  end

  def discovery
    get "/.well-known/openid-configuration"

    JSON.parse(response.body)
  end

  test "a pinned tenant answers at a hostname that names no subdomain of its own" do
    with_pinned(@tenant.subdomain) do
      host! "auth.example.test"

      assert_equal @tenant.uuid, discovery.dig("tenant", "uuid")
      assert_response :success
    end
  end

  test "every hostname reaches the same tenant, including the other tenant's own" do
    with_pinned(@tenant.subdomain) do
      [ "example.test", "auth.example.test", host_for(@other) ].each do |host|
        host! host

        assert_equal @tenant.uuid, discovery.dig("tenant", "uuid"), "#{host} resolved elsewhere"
      end
    end
  end

  test "a hostname that could never be a subdomain resolves anyway" do
    with_pinned(@tenant.subdomain) do
      host! "-nope-.example.test"

      assert_equal @tenant.uuid, discovery.dig("tenant", "uuid")
    end
  end

  test "the issuer follows the hostname unless an origin is pinned too" do
    with_pinned(@tenant.subdomain) do
      host! "auth.example.test"
      assert_equal "http://auth.example.test", discovery["issuer"]

      host! "elsewhere.example.test"
      assert_equal "http://elsewhere.example.test", discovery["issuer"]

      with_origin("https://auth.example.test") do
        assert_equal "https://auth.example.test", discovery["issuer"]

        host! "auth.example.test"
        assert_equal "https://auth.example.test", discovery["issuer"]
      end
    end
  end

  test "claiming is off while a tenant is pinned" do
    [ @tenant, @other ].each { |tenant| Tenant.switch(tenant) { tenant.destroy! } }

    with_pinned("fresh") do
      host! "auth.example.test"

      get "/login"

      assert_response :not_found
      refute Tenant.exists?
    end
  end

  test "the pinned tenant is created by the task the entrypoint runs" do
    with_pinned("fresh") do
      created = Tenant.declare!

      assert_equal [ "fresh" ], created.map(&:subdomain)
      assert_equal created.map(&:id), Tenant.declare!.map(&:id)
      assert created.sole.signing_key.kid.present?
    end
  end

  test "pinning one tenant and declaring several is a refusal, not a precedence rule" do
    with_pinned("fresh", declared: [ "declared" ]) do
      assert_raises(Tenant::TenancyConflict) { Tenant.declared }
      assert_raises(Tenant::TenancyConflict) { Tenant.declare! }
    end
  end

  test "the tenants nothing is pinned to still exist, and are simply unreachable" do
    with_pinned(@tenant.subdomain) do
      host! host_for(@other)

      assert_equal @tenant.uuid, discovery.dig("tenant", "uuid")
    end

    assert Tenant.active.exists?(id: @other.id)
  end
end
