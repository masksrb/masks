require "test_helper"

module Auth
  class ManageTest < AuthTestCase
    shared_tests

    def entry_params
      { path: "/login/masks.json" }
    end

    def client
      manage_client
    end

    test "#{@prefix} - internal tokens are required to log in managers" do
      get "/masks"

      assert_equal 302, status
      assert_login log_in("manager")

      get "/masks"

      assert_equal 200, status
    end
  end
end
