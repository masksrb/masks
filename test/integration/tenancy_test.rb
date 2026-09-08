require "test_helper"

class TenancyTest < ActionDispatch::IntegrationTest
  test "a hostname that serves no tenant is refused before the request reaches a controller" do
    host! "nobody.auth.test"

    get "/login"

    assert_response :not_found
    assert_equal Tenancy::Middleware::UNSERVED, response.body
  end

  test "the health check answers on a hostname that serves no tenant" do
    host! "localhost"

    get "/up"

    assert_response :success
  end

  test "a request leaves no tenant behind on the connection it borrowed" do
    create_actor(@tenant, nickname: "owner")

    host! host_for(@tenant)
    get "/login"

    assert_response :success
    assert_equal 0, Actor.unscoped.count,
                 "the request left its tenant on the connection, and the next request to " \
                 "borrow it would read this tenant's rows before resolving its own"
  end

  test "one tenant's request cannot see another's actors" do
    create_actor(@tenant, nickname: "owner", email: "owner@example.invalid")

    host! host_for(other_tenant)
    get "/login"

    assert_response :success
    assert_equal "setup", auth_data["prompt"],
                 "the other tenant has no actors of its own and must be asked to set up"
  end
end
