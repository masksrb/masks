require_relative "test_helper"

class EngineModeTest
  setup { host! "app.test" }

  test "discovery under a path names an issuer that includes the path" do
    get "/auth/.well-known/openid-configuration"

    assert_response :success
    discovery = JSON.parse(response.body)
    assert_equal "http://app.test/auth", discovery["issuer"]
    assert_equal "http://app.test/auth/authorize", discovery["authorization_endpoint"]
    assert_equal "http://app.test/auth/token", discovery["token_endpoint"]
    assert_equal "http://app.test/auth/.well-known/jwks.json", discovery["jwks_uri"]
  end

  test "discovery on a subdomain names an issuer with no path" do
    host! "auth.app.test"

    get "/.well-known/openid-configuration"

    assert_response :success
    assert_equal "http://auth.app.test", JSON.parse(response.body)["issuer"]
  end

  test "the host's own connections never carry a tenant, only the provider's do" do
    actor = create_actor

    assert_nil ActiveRecord::Base.connection.select_value("SELECT current_setting('masks.tenant_id', true)"),
               "the checkout hook named a tenant on the host app's pool"
    assert_equal tenant.id.to_s, Masks::Server::Tenant.switch(tenant) {
      Masks::Server::ApplicationRecord.connection.select_value("SELECT current_setting('masks.tenant_id', true)")
    }
    assert_equal actor.id, Masks::Server::Tenant.switch(tenant) { Masks::Server::Actor.find(actor.id).id }
  end

  test "a host page sends a stranger to the provider's sign-in, and back" do
    get "/dashboard"

    assert_redirected_to "/auth/login?return_to=%2Fdashboard"
  end

  test "the host reads the signed-in account straight from the provider's session" do
    actor = create_actor

    get "/auth/login", params: { return_to: "/dashboard" }
    body = sign_in(actor)

    assert body["settled"], body.inspect

    get "/dashboard"

    assert_response :success
    assert_equal actor.nickname, response.body
  end

  test "signing in returns to the host path the sign-in was started from" do
    actor = create_actor

    get "/auth/login", params: { return_to: "/dashboard" }
    body = sign_in(actor)

    assert_equal "/dashboard", body["redirectTo"]
  end

  test "the provider's own forms refuse a post without the form's token, whatever the host's defaults" do
    actor = create_actor

    get "/auth/login"
    sign_in(actor)

    held = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true

    assert_raises(ActionController::InvalidAuthenticityToken) do
      patch "/auth/account/password", params: { current_password: "password", password: "another long one" }
    end
  ensure
    ActionController::Base.allow_forgery_protection = held
  end

  test "a return address on another site is ignored" do
    actor = create_actor

    get "/auth/login", params: { return_to: "//evil.example/steal" }
    body = sign_in(actor)

    assert_not_includes body["redirectTo"].to_s, "evil.example"
  end

  test "the provider's session and the host's live in separate cookies" do
    post "/note", params: { note: "kept" }
    actor = create_actor
    sign_in(actor)

    assert cookies["_masks_session"].present?
    assert cookies["_host_session"].present?

    get "/note"

    assert_equal "kept", response.body, "signing in to masks must not reset the host's session"
  end

  test "the host's secret cannot read the provider's session cookie" do
    actor = create_actor
    sign_in(actor)

    host_jar = ActionDispatch::Request.new(
      Rails.application.env_config.merge("HTTP_COOKIE" => "masks_session=#{cookies['masks_session']}")
    ).cookie_jar

    assert_nil host_jar.encrypted[:masks_session]
  end

  test "the host's jobs are its own, and enqueue outside any tenant" do
    assert_nothing_raised { HostJob.perform_later }
    assert_not HostJob < Masks::Server::Tenancy::Job
  end

  test "the provider's encrypted columns use the engine's own key" do
    scheme = Masks::Server::Actor.type_for_attribute(:otp_secret).scheme

    assert_same Masks::Server.key_provider, scheme.key_provider
    assert_kind_of Masks::Server::TenantKeyProvider, scheme.key_provider
    assert_kind_of ActiveRecord::Encryption::KeyProvider, scheme.key_provider.shared
  end

  test "the provider encrypts each tenant's columns under that tenant's key in engine mode too" do
    scheme = Masks::Server::Actor.type_for_attribute(:otp_secret)
    ciphertext = Masks::Server::Tenant.switch(tenant) { scheme.serialize("JBSWY3DPEHPK3PXP") }

    assert_equal "JBSWY3DPEHPK3PXP", Masks::Server::Tenant.switch(tenant) { scheme.deserialize(ciphertext) }
    assert_raises(ActiveRecord::Encryption::Errors::Decryption) do
      ActiveRecord::Encryption.encryptor.decrypt(ciphertext, key_provider: Masks::Server.key_provider.shared)
    end
  end

  test "the provider runs on a database of its own" do
    assert_equal "masks_host_masks_test", Masks::Server::Tenant.connection_db_config.database
    assert_equal "masks_host_test", ActiveRecord::Base.connection_db_config.database
  end
end
