require "test_helper"

class ContentSecurityPolicyTest < ActionDispatch::IntegrationTest
  setup do
    host! host_for(@tenant)
  end

  test "the sign-in page runs only its own scripts and cannot be framed" do
    get "/login"

    policy = response.headers["Content-Security-Policy"]

    assert_includes policy, "script-src 'self'"
    assert_includes policy, "frame-ancestors 'none'"
    assert_includes policy, "object-src 'none'"
    assert_includes policy, "base-uri 'none'"
  end

  test "a picture keeps its own sealed policy" do
    actor = create_actor(@tenant)

    get "/avatars/#{actor.uuid}/initials"

    assert_equal ServesPictures::SEALED, response.headers["Content-Security-Policy"]
  end
end
