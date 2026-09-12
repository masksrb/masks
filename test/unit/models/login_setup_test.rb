require "test_helper"

class LoginSetupTest < ActiveSupport::TestCase
  PASSWORD = "a-long-enough-password".freeze

  setup do
    @store = {}
  end

  def step(event: nil, **updates)
    within do
      Login.new(store: @store, event: event, updates: updates).update
    end
  end

  def identify(nickname: "owner", email: "owner@example.invalid", **updates)
    step(event: "setup", nickname: nickname, email: email, **updates)
  end

  def credit(password: PASSWORD, confirmation: password)
    step(event: "setup", password: password, password_confirmation: confirmation)
  end

  def set_up(**updates)
    identify(**updates)
    credit
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

  test "the name and address are taken first, and nothing is created yet" do
    login = identify

    assert_equal "setup-confirm", login.prompt
    assert_nil login.actor
    assert_equal 0, within { Actor.count }
  end

  test "the confirmation screen reads back what was entered" do
    identify(nickname: "owner", email: "owner@example.invalid")

    published = step.as_json["setup"]

    assert_equal "owner", published["nickname"]
    assert_equal "owner@example.invalid", published["email"]
  end

  test "the password creates the owner, signs them in, and settles" do
    identify
    login = credit

    assert_equal "settled", login.prompt
    assert login.settled?
    assert_equal "owner", login.actor.nickname
    assert_equal "owner", login.identifier
  end

  test "one post that carries everything sets up without a second screen" do
    login = step(event: "setup", nickname: "owner", email: "owner@example.invalid",
                 password: PASSWORD, password_confirmation: PASSWORD)

    assert login.settled?
    assert_equal "owner", login.actor.nickname
  end

  test "a password the confirmation does not match creates nothing" do
    identify
    login = credit(password: PASSWORD, confirmation: "a-different-password")

    assert_equal "setup-confirm", login.prompt
    assert_includes login.warnings, "mismatched-password"
    assert_equal 0, within { Actor.count }
  end

  test "editing goes back to the first screen with the entries kept" do
    identify(nickname: "owner", email: "owner@example.invalid")

    login = step(event: "setup-edit")

    assert_equal "setup", login.prompt
    assert_equal "owner", login.as_json.dig("setup", "nickname")

    assert_equal "setup-confirm", identify(nickname: "second").prompt
    assert_equal "second", step.as_json.dig("setup", "nickname")
  end

  test "a password posted while editing creates nothing" do
    identify
    step(event: "setup-edit")

    login = credit

    assert_equal "setup", login.prompt
    assert_equal 0, within { Actor.count }
  end

  test "the owner holds the scopes masks defines, and masks:manage, and nothing else" do
    login = set_up

    assert_equal (Scopes::STANDARD + [ Scopes::MANAGE ]).sort, login.actor.scope_list.sort
  end

  test "an actor created any other way does not hold masks:manage" do
    login = set_up
    second = within { Actor.create!(nickname: "second", password: PASSWORD) }

    assert_includes login.actor.scope_list, Scopes::MANAGE
    refute_includes second.scope_list, Scopes::MANAGE
  end

  test "the owner can sign in afterwards with the password they chose" do
    set_up

    assert_equal "owner", within { Actor.authenticate("owner", PASSWORD) }&.nickname
  end

  test "the owner's email is required, and starts unconfirmed" do
    login = set_up

    assert_equal "owner@example.invalid", login.actor.email
    assert_nil login.actor.email_verified_at
  end

  test "setup without an email warns rather than moving on" do
    login = identify(nickname: "solo", email: nil)

    assert_equal "setup", login.prompt
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
    assert_equal "setup", within(other_tenant) {
      Login.new(store: {}, event: nil, updates: {}).update
    }.prompt
  end

  test "a blank nickname does not move on" do
    login = identify(nickname: " ")

    assert_equal "setup", login.prompt
    assert_includes login.warnings, "missing-nickname"
    assert_equal 0, within { Actor.count }
  end

  test "a short password does not create anything" do
    identify
    login = credit(password: "short")

    assert_equal "setup-confirm", login.prompt
    assert_includes login.warnings, "short-password"
    assert_equal 0, within { Actor.count }
  end

  test "a nickname the model refuses warns rather than raising" do
    identify(nickname: "-nope-")
    login = credit

    assert_equal "setup-confirm", login.prompt
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

      login = identify(token: "not-the-token")

      assert_equal "setup", login.prompt
      assert_includes login.warnings, "invalid-setup-token"
      assert_equal 0, within { Actor.count }
    end
  end

  test "a missing setup token is refused rather than treated as blank" do
    with_token("the-real-token") do
      login = identify

      assert_equal "setup", login.prompt
      assert_includes login.warnings, "invalid-setup-token"
      assert_equal 0, within { Actor.count }
    end
  end

  test "the right setup token gets past the first screen, and the owner is created" do
    with_token("the-real-token") do
      assert_equal "setup-confirm", identify(token: "the-real-token").prompt

      login = credit

      assert login.settled?
      assert_equal "owner", login.actor.nickname
    end
  end

  test "the setup key stops being published once the tenant has an owner" do
    with_token("the-real-token") do
      identify(token: "the-real-token")
      credit

      assert_nil step.as_json["setup"]
    end
  end
end
