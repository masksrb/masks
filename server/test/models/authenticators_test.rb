require "test_helper"

class AuthenticatorsTest < ActiveSupport::TestCase
  KEY = "ee882879-721c-4913-9775-3dfcce97072a".freeze
  BROKEN = "aaaaaaaa-0000-0000-0000-000000000001".freeze

  class FakeStatement
    attr_reader :description, :icon

    def initialize(description, icon = nil)
      @description = description
      @icon = icon
    end
  end

  class FakeReport
    attr_reader :status

    def initialize(status) = @status = status
  end

  class FakeEntry
    attr_reader :aaguid, :status_reports, :metadata_statement

    def initialize(aaguid, statuses, statement)
      @aaguid = aaguid
      @status_reports = statuses.map { |status| FakeReport.new(status) }
      @metadata_statement = statement
    end
  end

  class FakeStore
    def initialize(entries) = @entries = entries

    def table_of_contents = Struct.new(:entries).new(@entries)
  end

  class RefusingStore
    def table_of_contents = raise(SocketError, "no route to the metadata service")
  end

  def store(*entries)
    FakeStore.new(entries)
  end

  test "an entry becomes an authenticator, named by its statement" do
    Authenticators.refresh!(store: store(
      FakeEntry.new(KEY, [ "FIDO_CERTIFIED_L2" ], FakeStatement.new("YubiKey 5 Series", "data:image/png;base64,AA"))
    ))

    held = Authenticator.describing(KEY)

    assert_equal "YubiKey 5 Series", held.name
    assert_equal "FIDO_CERTIFIED_L2", held.certification
    assert_equal "data:image/png;base64,AA", held.icon
    assert held.certified?
    assert_not held.compromised?
  end

  test "a reported compromise is recorded, and a certification alone is not one" do
    Authenticators.refresh!(store: store(
      FakeEntry.new(BROKEN, [ "FIDO_CERTIFIED", "USER_VERIFICATION_BYPASS" ], FakeStatement.new("Leaky Key")),
      FakeEntry.new(KEY, [ "FIDO_CERTIFIED_L2" ], FakeStatement.new("YubiKey 5 Series"))
    ))

    assert Authenticator.describing(BROKEN).compromised?
    assert_equal "USER_VERIFICATION_BYPASS", Authenticator.describing(BROKEN).compromise
    assert_not Authenticator.describing(KEY).compromised?
    assert_equal [ BROKEN ], Authenticator.compromised.pluck(:aaguid)
  end

  test "a compromise that is later withdrawn stops being reported" do
    Authenticators.refresh!(store: store(
      FakeEntry.new(BROKEN, [ "REVOKED" ], FakeStatement.new("Leaky Key"))
    ))
    assert Authenticator.describing(BROKEN).compromised?

    Authenticators.refresh!(store: store(
      FakeEntry.new(BROKEN, [ "FIDO_CERTIFIED" ], FakeStatement.new("Leaky Key"))
    ))

    assert_not Authenticator.describing(BROKEN).reload.compromised?
  end

  test "bundled names fill gaps the metadata service leaves" do
    Authenticators.refresh!(store: store)

    held = Authenticator.describing("fbfc3007-154e-4ecc-8c0b-6e020557d7bd")

    assert_equal "iCloud Keychain", held.name
    assert_equal Authenticator::BUNDLED, held.source
    assert_not held.certified?
    assert_not held.compromised?
  end

  test "a bundled name never overwrites what the metadata service said" do
    apple = "fbfc3007-154e-4ecc-8c0b-6e020557d7bd"

    Authenticators.refresh!(store: store(
      FakeEntry.new(apple, [ "FIDO_CERTIFIED" ], FakeStatement.new("Apple Passkey, per MDS"))
    ))

    held = Authenticator.describing(apple)

    assert_equal "Apple Passkey, per MDS", held.name
    assert_equal Authenticator::MDS, held.source
  end

  test "an unreachable metadata service fails loudly and changes nothing" do
    Authenticators.refresh!(store: store(
      FakeEntry.new(KEY, [ "FIDO_CERTIFIED" ], FakeStatement.new("YubiKey 5 Series"))
    ))

    assert_raises(Authenticators::Unreachable) do
      Authenticators.refresh!(store: RefusingStore.new)
    end

    assert_equal "YubiKey 5 Series", Authenticator.describing(KEY).name
  end

  test "an entry with no aaguid is skipped rather than stored under a blank key" do
    Authenticators.refresh!(store: store(
      FakeEntry.new(nil, [ "FIDO_CERTIFIED" ], FakeStatement.new("A UAF authenticator"))
    ))

    assert_equal 0, Authenticator.where(source: Authenticator::MDS).count
  end

  test "nothing is known before a refresh, and describing an unknown aaguid is nil" do
    assert_nil Authenticator.describing("00000000-0000-0000-0000-000000000000")
    assert_nil Authenticator.describing(nil)
  end
end
