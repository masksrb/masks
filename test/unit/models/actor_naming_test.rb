require "test_helper"

class ActorNamingTest < ActiveSupport::TestCase
  PASSWORD = "a-long-enough-password".freeze

  def named_by(rule)
    @tenant.update!(named_by: rule)
  end

  def pinned(rule)
    was = Rails.configuration.masks.named_by
    Rails.configuration.masks.named_by = rule
    yield
  ensure
    Rails.configuration.masks.named_by = was
  end

  def actor(**attributes)
    within { Actor.new(password: PASSWORD, **attributes) }
  end

  test "a tenant names accounts by either half until it is told otherwise" do
    assert_equal Tenant::EITHER, @tenant.named_by
  end

  test "a rule the deployment pins wins over the one the tenant holds" do
    named_by(Tenant::NICKNAME)

    pinned(Tenant::EMAIL) do
      assert_equal Tenant::EMAIL, @tenant.named_by
      assert @tenant.names_pinned?
    end

    assert_equal Tenant::NICKNAME, @tenant.reload.named_by
    refute @tenant.names_pinned?
  end

  test "a rule masks does not know is not a rule a tenant can hold" do
    refute @tenant.update(named_by: "whatever")
    assert_includes @tenant.errors.attribute_names, :named_by
  end

  test "either half names an account on its own" do
    named_by(Tenant::EITHER)

    assert actor(nickname: "ada").valid?
    assert actor(email: "ada@example.invalid").valid?
  end

  test "an account with neither half is refused, whatever the rule says" do
    Tenant::NAMES.each do |rule|
      named_by(rule)

      nameless = actor

      refute nameless.valid?, "#{rule} let an account through with no name at all"
    end
  end

  test "a tenant named by nickname insists on one" do
    named_by(Tenant::NICKNAME)

    refute actor(email: "ada@example.invalid").valid?
    assert actor(nickname: "ada").valid?
  end

  test "a tenant named by address insists on one" do
    named_by(Tenant::EMAIL)

    refute actor(nickname: "ada").valid?
    assert actor(email: "ada@example.invalid").valid?
  end

  test "a manager needs both halves, whatever the tenant is named by" do
    Tenant::NAMES.each do |rule|
      named_by(rule)

      manager = actor(nickname: "ada", scopes: Scopes.join([ Scopes::MANAGE ]))

      refute manager.valid?, "#{rule} let a manager through without an address"
      assert_includes manager.errors.attribute_names, :email

      manager.email = "ada@example.invalid"

      assert manager.valid?, "#{rule} refused a manager holding both"
    end
  end

  test "an account cannot be handed masks:manage while half named" do
    named_by(Tenant::EITHER)

    ada = within { Actor.create!(email: "ada@example.invalid", password: PASSWORD) }

    refute within { ada.update(scopes: Scopes.join([ Scopes::MANAGE ])) }
    assert_includes ada.errors.attribute_names, :nickname
  end

  test "the database refuses a nameless account even with the model out of the way" do
    assert_raises ActiveRecord::StatementInvalid do
      within { Actor.new(password: PASSWORD).save!(validate: false) }
    end
  end

  test "an account answers with whichever half it has" do
    within do
      assert_equal "ada", Actor.new(nickname: "ada", email: "ada@example.invalid").identifier
      assert_equal "ada", Actor.new(nickname: "ada").identifier
      assert_equal "ada@example.invalid", Actor.new(email: "ada@example.invalid").identifier
    end
  end

  test "an account is found by either half" do
    named_by(Tenant::EITHER)

    ada = within { Actor.create!(email: "ada@example.invalid", password: PASSWORD) }
    bob = within { Actor.create!(nickname: "bob", password: PASSWORD) }

    within do
      assert_equal ada.id, Actor.locate("ada@example.invalid").id
      assert_equal bob.id, Actor.locate("bob").id
      assert_nil Actor.locate("")
      assert_nil Actor.locate(nil)
    end
  end

  test "two accounts without nicknames do not collide on the empty one" do
    named_by(Tenant::EMAIL)

    within do
      assert Actor.create!(email: "one@example.invalid", password: PASSWORD).persisted?
      assert Actor.create!(email: "two@example.invalid", password: PASSWORD).persisted?
    end
  end
end
