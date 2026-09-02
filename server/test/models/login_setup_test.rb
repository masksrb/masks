require "test_helper"

class LoginSetupTest < ActiveSupport::TestCase
  setup do
    @store = {}
  end

  def step(event: nil, **updates)
    within do
      Login.new(store: @store, event: event, updates: updates).update
    end
  end

  def with_token(value)
    was = Rails.configuration.masks.setup_token
    Rails.configuration.masks.setup_token = value
    yield
  ensure
    Rails.configuration.masks.setup_token = was
  end

  test "a tenant with no actors asks to be set up before it asks who you are" do
    assert_equal "setup", step.prompt
  end

  test "setup creates the owner, signs them in, and settles in one step" do
    login = step(event: "setup", nickname: "owner", email: "owner@example.invalid",
                 password: "a-long-enough-password")

    assert_equal "settled", login.prompt
    assert login.settled?
    assert_equal "owner", login.actor.nickname
    assert_equal "owner", login.identifier
  end

  test "the owner holds the scopes masks defines, and masks:manage, and nothing else" do
    login = step(event: "setup", nickname: "owner", email: "owner@example.invalid", password: "a-long-enough-password")

    assert_equal (Scopes::STANDARD + [ Scopes::MANAGE ]).sort, login.actor.scope_list.sort
  end

  test "an actor created any other way does not hold masks:manage" do
    login = step(event: "setup", nickname: "owner", email: "owner@example.invalid", password: "a-long-enough-password")
    second = within { Actor.create!(nickname: "second", password: "a-long-enough-password") }

    assert_includes login.actor.scope_list, Scopes::MANAGE
    refute_includes second.scope_list, Scopes::MANAGE
  end

  test "the owner can sign in afterwards with the password they chose" do
    step(event: "setup", nickname: "owner", email: "owner@example.invalid", password: "a-long-enough-password")

    assert_equal "owner", within { Actor.authenticate("owner", "a-long-enough-password") }&.nickname
  end

  test "the owner's email is required, and recorded as verified" do
    login = step(event: "setup", nickname: "owner", email: "owner@example.invalid",
                 password: "a-long-enough-password")

    assert_equal "owner@example.invalid", login.actor.email
    assert login.actor.email_verified_at.present?
  end

  test "setup without an email warns rather than creating an owner nothing can consume" do
    login = step(event: "setup", nickname: "solo", password: "a-long-enough-password")

    assert_nil login.actor
    assert_includes login.warnings, "missing-email"
    assert_equal 0, within { Actor.count }
  end

  test "the prompt is gone the moment an actor exists" do
    create_actor

    assert_equal "identify", step.prompt
  end

  test "a second tenant is set up independently of the first" do
    create_actor

    assert_equal "identify", step.prompt
    assert_equal "setup", within(@other) {
      Login.new(store: {}, event: nil, updates: {}).update
    }.prompt
  end

  test "a blank username does not create anything" do
    login = step(event: "setup", nickname: " ", email: "owner@example.invalid", password: "a-long-enough-password")

    assert_equal "setup", login.prompt
    assert_includes login.warnings, "missing-nickname"
    assert_equal 0, within { Actor.count }
  end

  test "a short password does not create anything" do
    login = step(event: "setup", nickname: "owner", email: "owner@example.invalid", password: "short")

    assert_equal "setup", login.prompt
    assert_includes login.warnings, "short-password"
    assert_equal 0, within { Actor.count }
  end

  test "a username the model refuses warns rather than raising" do
    login = step(event: "setup", nickname: "-nope-", email: "owner@example.invalid", password: "a-long-enough-password")

    assert_equal "setup", login.prompt
    assert_includes login.warnings, "invalid-account"
    assert_equal 0, within { Actor.count }
  end

  test "no setup token configured means none is asked for" do
    refute LoginStates::Setup.token_required?
    refute step.as_json.dig("setup", "token")
  end

  test "a configured setup token is required, and a wrong one creates nothing" do
    with_token("the-real-token") do
      assert step.as_json.dig("setup", "token")

      login = step(event: "setup", nickname: "owner", email: "owner@example.invalid", password: "a-long-enough-password",
                   token: "not-the-token")

      assert_equal "setup", login.prompt
      assert_includes login.warnings, "invalid-setup-token"
      assert_equal 0, within { Actor.count }
    end
  end

  test "a missing setup token is refused rather than treated as blank" do
    with_token("the-real-token") do
      login = step(event: "setup", nickname: "owner", email: "owner@example.invalid", password: "a-long-enough-password")

      assert_includes login.warnings, "invalid-setup-token"
      assert_equal 0, within { Actor.count }
    end
  end

  test "the right setup token creates the owner" do
    with_token("the-real-token") do
      login = step(event: "setup", nickname: "owner", email: "owner@example.invalid", password: "a-long-enough-password",
                   token: "the-real-token")

      assert login.settled?
      assert_equal "owner", login.actor.nickname
    end
  end

  test "the setup key stops being published once the tenant has an owner" do
    with_token("the-real-token") do
      step(event: "setup", nickname: "owner", email: "owner@example.invalid", password: "a-long-enough-password",
           token: "the-real-token")

      assert_nil step.as_json["setup"]
    end
  end
end
