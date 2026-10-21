module Masks
  module Server
    require "test_helper"

    class ReleaseCheckJobTest < ActiveSupport::TestCase
      def checking
        settings = ::Rails.configuration.masks
        was = settings.release_check
        settings.release_check = true

        yield
      ensure
        settings.release_check = was
      end

      def releases(*entries)
        entries.map do |tag, body = "", flags = {}|
          { tag_name: tag, html_url: "https://github.com/masksrb/masks/releases/tag/#{tag}", body: body,
            draft: flags.fetch(:draft, false), prerelease: flags.fetch(:prerelease, false) }
        end.to_json
      end

      def published(body)
        stub_request(:get, Release::URL).to_return(status: 200, body: body, headers: { "Content-Type" => "application/json" })
      end

      def announced(tenant = @tenant)
        within(tenant) { Event.where(action: Event::RELEASE_AVAILABLE).order(:id).to_a }
      end

      setup { Release.forget! }

      test "nothing is fetched while the check is off" do
        published(releases([ "server-v9.9.9" ]))

        ReleaseCheckJob.perform_now

        assert_not_requested :get, Release::URL
        assert_nil Release.latest
      end

      test "a newer server release is remembered, shown as available, and announced once in every tenant" do
        other = other_tenant
        published(releases([ "python-v9.9.9" ], [ "server-v9.9.9", "## Changes\n\nOperator: run bin/rails masks:keys once." ], [ "server-v9.9.8" ]))

        checking { ReleaseCheckJob.perform_now }

        found = Release.available

        assert_equal "9.9.9", found["version"]
        assert_equal "https://github.com/masksrb/masks/releases/tag/server-v9.9.9", found["url"]
        assert found["operator_step"]
        assert_equal 1, announced.size
        assert_equal 1, announced(other).size
        assert_equal({ "version" => "9.9.9", "url" => found["url"], "operator_step" => true }, announced.first.details)

        checking { ReleaseCheckJob.perform_now }

        assert_equal 1, announced.size, "the same version is announced once"
        assert_requested :get, Release::URL, times: 2
      end

      test "the request carries the server's version and nothing else" do
        published(releases([ "server-v9.9.9" ]))

        checking { ReleaseCheckJob.perform_now }

        assert_requested(:get, Release::URL) do |request|
          request.headers["User-Agent"] == "masks-server/#{VERSION}" && request.body.blank? &&
            request.headers.keys.none? { |name| name.casecmp?("Authorization") || name.casecmp?("Cookie") }
        end
      end

      test "a release no newer than this server is remembered and not available" do
        published(releases([ "server-v0.0.1", "Operator: nothing" ]))

        checking { ReleaseCheckJob.perform_now }

        assert_equal "0.0.1", Release.latest["version"]
        assert_nil Release.available
        assert_empty announced
      end

      test "drafts, prereleases, and other packages' tags are skipped" do
        published(releases([ "server-v9.9.9", "", { draft: true } ], [ "server-v9.9.8", "", { prerelease: true } ],
                           [ "masks-server-v9.9.7" ], [ "gem/v9.9.6" ], [ "server-v9.9.5" ]))

        checking { ReleaseCheckJob.perform_now }

        assert_equal "9.9.5", Release.available["version"]
        assert_not Release.available["operator_step"]
      end

      test "a timeout keeps the last good answer and announces nothing" do
        Release.remember!({ "version" => "9.9.9", "url" => "https://github.com/masksrb/masks/releases/tag/server-v9.9.9",
                            "operator_step" => false, "checked_at" => 1.day.ago.utc.iso8601 })
        stub_request(:get, Release::URL).to_timeout

        checking { assert_nothing_raised { ReleaseCheckJob.perform_now } }

        assert_equal "9.9.9", Release.latest["version"]
        assert_empty announced
      end

      test "a malformed body keeps the last good answer" do
        Release.remember!({ "version" => "9.9.9", "url" => "https://github.com/masksrb/masks/releases/tag/server-v9.9.9",
                            "operator_step" => false, "checked_at" => 1.day.ago.utc.iso8601 })
        published("<html>rate limited</html>")

        checking { assert_nothing_raised { ReleaseCheckJob.perform_now } }

        assert_equal "9.9.9", Release.latest["version"]

        published({ "message" => "not a list" }.to_json)

        checking { assert_nothing_raised { ReleaseCheckJob.perform_now } }

        assert_equal "9.9.9", Release.latest["version"]
      end

      test "a refusal keeps the last good answer" do
        stub_request(:get, Release::URL).to_return(status: 403, body: "")

        checking { assert_nothing_raised { ReleaseCheckJob.perform_now } }

        assert_nil Release.latest
      end

      test "a version that is not a version is never newer" do
        assert_not Release.newer?("banana")
        assert_not Release.newer?(VERSION)
        assert Release.newer?("99.0.0")
      end
    end
  end
end
