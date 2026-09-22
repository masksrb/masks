module Masks
  module Server
    require "test_helper"

    class AgentRulesTest < ActiveSupport::TestCase
      CHROME = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 " \
               "(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36".freeze
      PHONE = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 " \
              "(KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1".freeze

      test "a browser is a browser, and a script, a crawler and a silence are not" do
        assert Device.browser?(CHROME)
        assert Device.browser?(PHONE)

        refute Device.browser?("curl/8.7.1")
        refute Device.browser?("python-requests/2.31.0")
        refute Device.browser?("Googlebot/2.1 (+http://www.google.com/bot.html)")
        refute Device.browser?("")
        refute Device.browser?(nil)
      end

      test "a tenant refuses nothing until it is told to" do
        refute @tenant.refuses?("curl/8.7.1")
        refute @tenant.refuses?(CHROME)
        refute @tenant.refuses?(nil)
      end

      test "browsers only turns away everything that is not one" do
        @tenant.update!(browsers_only: true)

        assert @tenant.refuses?("curl/8.7.1")
        assert @tenant.refuses?("Googlebot/2.1")
        assert @tenant.refuses?("")
        refute @tenant.refuses?(CHROME)
      end

      test "a deployment can pin both rules, and the tenant cannot argue" do
        was_browsers = ::Rails.configuration.masks.browsers_only
        was_agents = ::Rails.configuration.masks.blocked_agents

        ::Rails.configuration.masks.browsers_only = "true"
        ::Rails.configuration.masks.blocked_agents = "wget"

        @tenant.update!(browsers_only: false, blocked_agents: "curl")

        assert @tenant.browsers_only
        assert @tenant.browsers_pinned?
        assert_equal %w[wget], @tenant.agent_list
        assert @tenant.refuses?("curl/8.7.1")
      ensure
        ::Rails.configuration.masks.browsers_only = was_browsers
        ::Rails.configuration.masks.blocked_agents = was_agents
      end

      test "a named agent is refused wherever it appears in the string, whatever its case" do
        @tenant.update!(blocked_agents: "curl\npython-requests , wget")

        assert_equal %w[curl python-requests wget], @tenant.agent_list

        assert @tenant.refuses?("curl/8.7.1")
        assert @tenant.refuses?("Curl/8.7.1")
        assert @tenant.refuses?("Mozilla/5.0 python-requests/2.31.0")
        refute @tenant.refuses?(CHROME)
        refute @tenant.refuses?(nil)
      end
    end
  end
end
