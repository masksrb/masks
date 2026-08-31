require "test_helper"

class BackupCodesTest < ActionDispatch::IntegrationTest
  setup do
    host! host_for(@tenant)
    @actor = create_actor(@tenant)
    @totp = enable_otp(@actor)
    @codes = within(@tenant) { @actor.generate_backup_codes! }
  end

  def prompt
    JSON.parse(response.body)["prompt"]
  end

  def event(name, **updates)
    post "/login", params: { event: name }.merge(updates), as: :json

    JSON.parse(response.body)
  end

  def to_second_factor
    event("identify", identifier: @actor.nickname)
    event("password", password: "password")
  end

  test "codes are returned once and stored as digests" do
    assert_equal Actor::BACKUP_CODES, @codes.length
    assert_equal @codes.uniq.length, @codes.length

    within(@tenant) do
      raw = Actor.connection.select_value(
        "SELECT backup_code_digests::text FROM actors WHERE id = #{@actor.id}"
      )

      @codes.each { |code| assert_not_includes raw, code }
      assert_equal Actor::BACKUP_CODES, JSON.parse(raw).length
    end
  end

  test "a code is a second factor, and the same one never works twice" do
    to_second_factor

    assert_equal "second-factor", prompt

    body = event("use-backup-code")
    assert_equal "backup-code", body["prompt"]
    assert_equal Actor::BACKUP_CODES, body.dig("backupCodes", "remaining")

    settled = event("backup", backup_code: @codes.first)

    assert settled["settled"], settled.inspect

    within(@tenant) do
      assert_equal Actor::BACKUP_CODES - 1, @actor.reload.backup_codes_remaining
    end

    delete "/login"
    to_second_factor
    event("use-backup-code")

    replayed = event("backup", backup_code: @codes.first)

    assert_not replayed["settled"]
    assert_includes replayed["warnings"], "invalid-backup-code"
  end

  test "a wrong code is refused and spends nothing" do
    to_second_factor
    event("use-backup-code")

    refused = event("backup", backup_code: "0000000000000000")

    assert_not refused["settled"]
    assert_includes refused["warnings"], "invalid-backup-code"

    within(@tenant) do
      assert_equal Actor::BACKUP_CODES, @actor.reload.backup_codes_remaining
    end
  end

  test "a backup code cannot stand in for the first factor" do
    event("identify", identifier: @actor.nickname)

    refused = event("backup", backup_code: @codes.first)

    assert_not refused["settled"]
    assert_not_equal "settled", refused["prompt"]

    within(@tenant) do
      assert_equal Actor::BACKUP_CODES, @actor.reload.backup_codes_remaining,
                   "a code must not be spent by a login that never proved a first factor"
    end
  end

  test "a first factor that has expired does not let a backup code through" do
    to_second_factor
    event("use-backup-code")

    travel LoginStates::Password::EXPIRY + 1.minute do
      refused = event("backup", backup_code: @codes.first)

      assert_not refused["settled"]
      assert_includes refused["warnings"], "missing-first-factor"

      within(@tenant) do
        assert_equal Actor::BACKUP_CODES, @actor.reload.backup_codes_remaining
      end
    end
  end

  test "the authenticator still works, and going back to it is one event" do
    to_second_factor
    event("use-backup-code")

    assert_equal "backup-code", prompt

    assert_equal "second-factor", event("use-authenticator")["prompt"]

    settled = event("otp", code: @totp.now)

    assert settled["settled"]
  end

  test "an actor with no codes is never offered them" do
    bare = create_actor(@tenant, nickname: "bare")
    enable_otp(bare)

    event("identify", identifier: bare.nickname)
    event("password", password: "password")

    body = event("use-backup-code")

    assert_equal "second-factor", body["prompt"], "there is nothing to fall back to"
    assert_nil body["backupCodes"]
  end

  test "regenerating replaces every code rather than adding to them" do
    within(@tenant) do
      again = @actor.generate_backup_codes!

      assert_equal Actor::BACKUP_CODES, @actor.reload.backup_codes_remaining
      assert_empty(@codes & again)
      assert_not @actor.verify_backup_code(@codes.first)
      assert @actor.verify_backup_code(again.first)
    end
  end

  test "a code is read the way somebody would type it back" do
    within(@tenant) do
      spaced = @codes.first.upcase.scan(/..../).join(" ")

      assert @actor.verify_backup_code(spaced)
    end
  end
end
