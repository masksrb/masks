require_relative "test_helper"

class OrganizationTest < EngineIntegrationTest
  def signed_in_to(organization = nil)
    connect!

    get organization ? "/auth?organization=#{organization}" : "/auth", headers: host
    landed = issuer.authorize!(response.location)

    get "/auth/callback?code=#{landed[:code]}&state=#{landed[:state]}", headers: host

    landed
  end

  def account
    get "/auth/session", headers: host.merge("HTTP_ACCEPT" => "application/json")

    json
  end

  test "an organization named on the way in travels to authorize" do
    landed = signed_in_to("acme")

    assert_equal [ "acme" ], landed[:query]["organization"]
  end

  test "a key that could not be an organization's is dropped rather than sent" do
    landed = signed_in_to(CGI.escape("acme&prompt=none"))

    assert_nil landed[:query]["organization"]
    assert_nil landed[:query]["prompt"]
  end

  test "an app can name the organization from the request" do
    configure!(organization: ->(request) { request.params[:tenant_org] })
    connect!

    get "/auth?tenant_org=globex", headers: host

    assert_equal "globex", URI.decode_www_form(URI.parse(response.location).query).to_h["organization"]
  end

  test "the account names the organization and the role held in it" do
    issuer.role = "owner"
    signed_in_to("acme")

    assert_equal({ "id" => "org-acme", "key" => "acme", "name" => "Acme", "role" => "owner" }, account["organization"])
  end

  test "an account signed in without an organization names none" do
    signed_in_to

    assert_nil account["organization"]
  end

  test "a page for owners lets an owner in" do
    issuer.role = "owner"
    signed_in_to("acme")

    get "/owners", headers: host

    assert_response :success
    assert_equal "owners of acme", response.body
  end

  test "a page for owners refuses a member, and says why" do
    signed_in_to("acme")

    get "/owners", headers: host.merge("HTTP_ACCEPT" => "application/json")

    assert_response :forbidden
    assert_equal "insufficient_role", json["error"]
    assert_equal "no-store", response.headers["Cache-Control"]
  end

  test "a page for owners refuses a person signed in to no organization" do
    signed_in_to

    get "/owners", headers: host.merge("HTTP_ACCEPT" => "application/json")

    assert_response :forbidden
    assert_equal "insufficient_organization", json["error"]
  end

  test "a page for owners sends a signed-out browser to sign in first" do
    connect!

    get "/owners", headers: host

    assert_redirected_to "/auth/"
  end

  test "a refresh picks up the role the person holds now" do
    signed_in_to("acme")

    issuer.role = "owner"

    travel 2.hours do
      assert_equal "owner", account.dig("organization", "role")

      get "/owners", headers: host

      assert_response :success
    end
  end
end
