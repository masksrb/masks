require "test_helper"

class TenantMailTest < ActiveSupport::TestCase
  def with_deployment(from: nil, settings: nil)
    was_from = Rails.configuration.masks.mail_from
    was_settings = ActionMailer::Base.smtp_settings

    Rails.configuration.masks.mail_from = from
    ActionMailer::Base.smtp_settings = settings || {}
    yield
  ensure
    Rails.configuration.masks.mail_from = was_from
    ActionMailer::Base.smtp_settings = was_settings
  end

  def mails!(**attributes)
    @tenant.update!(
      { mail_from: "masks@example.invalid", smtp_address: "smtp.example.invalid" }
        .merge(attributes)
    )
  end

  test "a tenant that holds nothing mails on whatever the deployment configured" do
    with_deployment(from: "deploy@example.invalid", settings: { address: "relay.example.invalid" }) do
      assert @tenant.mails?
      assert_equal "deploy@example.invalid", @tenant.mail_from
      assert_equal({ address: "relay.example.invalid" }, @tenant.smtp_settings)
      refute @tenant.own_smtp?
    end
  end

  test "a deployment with no mailer mails nowhere" do
    with_deployment do
      refute @tenant.mails?
      assert_nil @tenant.smtp_settings
    end
  end

  test "a tenant with a server of its own answers with its own settings" do
    with_deployment(from: "deploy@example.invalid", settings: { address: "relay.example.invalid" }) do
      mails!(smtp_port: 2525, smtp_username: "postmaster", smtp_password: "hunter2",
             smtp_authentication: "login", smtp_domain: "example.invalid", smtp_tls: true)

      settings = @tenant.smtp_settings

      assert @tenant.own_smtp?
      assert_equal "masks@example.invalid", @tenant.mail_from
      assert_equal "smtp.example.invalid", settings[:address]
      assert_equal 2525, settings[:port]
      assert_equal "postmaster", settings[:user_name]
      assert_equal "hunter2", settings[:password]
      assert_equal :login, settings[:authentication]
      assert_equal "example.invalid", settings[:domain]
      assert settings[:tls]
      refute settings[:enable_starttls]
      assert_equal OpenSSL::SSL::VERIFY_PEER, settings[:openssl_verify_mode]
    end
  end

  test "a server with no port of its own is reached on the submission port" do
    mails!

    assert_equal Tenant::SMTP_PORT, @tenant.smtp_settings[:port]
    assert_equal :plain, @tenant.smtp_settings[:authentication]
    refute @tenant.smtp_settings[:tls]
    assert @tenant.smtp_settings[:enable_starttls]
  end

  test "the password is encrypted at rest" do
    mails!(smtp_password: "hunter2")

    held = Tenant.connection.select_value(
      Tenant.sanitize_sql([ "SELECT smtp_password FROM tenants WHERE id = ?", @tenant.id ])
    )

    refute_equal "hunter2", held
    refute_includes held, "hunter2"
    assert_equal "hunter2", @tenant.reload.smtp_password
  end

  test "a port outside the range, and an authentication masks cannot speak, are refused" do
    refute @tenant.update(smtp_port: 0)
    assert_includes @tenant.errors.attribute_names, :smtp_port

    refute @tenant.reload.update(smtp_authentication: "telepathy")
    assert_includes @tenant.errors.attribute_names, :smtp_authentication

    refute @tenant.reload.update(mail_from: "not-an-address")
    assert_includes @tenant.errors.attribute_names, :mail_from
  end

  test "a message built for a tenant carries that tenant's server" do
    mails!(smtp_port: 2525, smtp_username: "postmaster", smtp_password: "hunter2")

    actor = create_actor(@tenant, nickname: "ada", email: "ada@example.invalid")

    message = Tenant.switch(@tenant) do
      held = ActorMailer.invitation(actor, "https://masks.example.invalid/a",
                                    tenant_name: @tenant.name)
      held.message # the mail is lazy, and the tenant has to still be here when it is built
      held
    end

    assert_equal [ "masks@example.invalid" ], message.from
    assert_equal "smtp.example.invalid", message.delivery_method.settings[:address]
    assert_equal 2525, message.delivery_method.settings[:port]
  end

  test "a tenant without a server of its own leaves delivery where the deployment put it" do
    with_deployment(from: "deploy@example.invalid", settings: { address: "relay.example.invalid" }) do
      actor = create_actor(@tenant, nickname: "ada", email: "ada@example.invalid")

      message = Tenant.switch(@tenant) do
        held = ActorMailer.invitation(actor, "https://masks.example.invalid/a",
                                      tenant_name: @tenant.name)
        held.message
        held
      end

      assert_equal [ "deploy@example.invalid" ], message.from
      assert_kind_of Mail::TestMailer, message.delivery_method
    end
  end
end
