require "test_helper"

class RefreshAuthenticatorsJobTest < ActiveSupport::TestCase
  KEY = "ee882879-721c-4913-9775-3dfcce97072a".freeze

  class FakeStatement
    attr_reader :description, :icon

    def initialize(description) = @description = description

    def icon = nil
  end

  class FakeEntry
    attr_reader :aaguid, :status_reports, :metadata_statement

    def initialize(aaguid, statement)
      @aaguid = aaguid
      @status_reports = []
      @metadata_statement = statement
    end
  end

  class FakeStore
    def table_of_contents
      Struct.new(:entries).new([ FakeEntry.new(KEY, FakeStatement.new("YubiKey 5 Series")) ])
    end
  end

  class RefusingStore
    def table_of_contents = raise(SocketError, "no route to the metadata service")
  end

  test "the schedule reaches the metadata service holding no tenant of its own" do
    assert_nothing_raised { RefreshAuthenticatorsJob.perform_now(store: FakeStore.new) }

    assert_equal "YubiKey 5 Series", Authenticator.describing(KEY).name
  end

  test "a metadata service that cannot be read leaves the schedule to try again tomorrow" do
    assert_nothing_raised { RefreshAuthenticatorsJob.perform_now(store: RefusingStore.new) }
  end
end
