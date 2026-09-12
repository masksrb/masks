require "test_helper"

class FirstRunTest < ActionDispatch::IntegrationTest
  PASSWORD = "a-long-enough-password".freeze

  def setup_params(**overrides)
    { event: "setup", nickname: "owner", email: "owner@example.invalid",
      password: PASSWORD, password_confirmation: PASSWORD,
      named_by: Tenant::EITHER }.merge(overrides)
  end

  def identify_params(**overrides)
    { event: "setup", nickname: "owner", email: "owner@example.invalid" }.merge(overrides)
  end

  def with_declared(list)
    was = Rails.configuration.masks.tenants
    Rails.configuration.masks.tenants = list
    yield
  ensure
    Rails.configuration.masks.tenants = was
  end

  def with_nothing_deployed
    [ @tenant, other_tenant ].each { |tenant| Tenant.switch(tenant) { tenant.destroy! } }

    yield
  end

  test "a tenant with no actors asks to be set up, and says so in both renderings" do
    host! host_for(@tenant)

    get "/login"

    assert_response :success
    assert_match "Set up", response.body
    assert_match "<em>#{@tenant.name}</em>", response.body
    assert_match "Continue", response.body
    assert_match "This screen will not appear again", response.body

    post "/login", params: { event: "start-over" }, as: :json

    assert_equal "setup", JSON.parse(response.body)["prompt"]
  end

  test "the root of an empty tenant goes straight to the only thing that can happen there" do
    host! host_for(@tenant)

    get "/"

    assert_redirected_to login_path

    follow_redirect!

    assert_response :success
    assert_match "Set up", response.body
    assert_select "a[href=?]", Rails.configuration.masks.docs_url
  end

  test "the root stops being a first run as soon as an actor exists" do
    create_actor(@tenant, nickname: "owner", password: PASSWORD)
    host! host_for(@tenant)

    get "/"

    assert_response :success
    assert_match "Your account", response.body
    assert_select "a[href=?]", manage_path, false
  end

  test "three screens: the manager, their password, and what masks is configured to do" do
    host! host_for(@tenant)

    get "/login"

    assert_match "Identification", response.body
    assert_match "Credentials", response.body
    assert_match "Configuration", response.body

    post "/login", params: identify_params, as: :json
    body = JSON.parse(response.body)

    assert_equal "setup-password", body["prompt"]
    assert_equal "owner", body.dig("setup", "nickname")
    assert_equal 0, within(@tenant) { Actor.count }

    get "/login"

    assert_response :success
    assert_match "Create the manager", response.body
    assert_match "Confirm password", response.body

    post "/login", params: { event: "setup", password: PASSWORD,
                             password_confirmation: PASSWORD }, as: :json
    body = JSON.parse(response.body)

    assert_equal "setup-configure", body["prompt"]
    assert_equal "owner", within(@tenant) { Actor.sole.nickname }

    get "/login"

    assert_match "An account is named by", response.body
    assert_match "Managers always need both", response.body

    post "/login", params: { event: "setup-configure", named_by: Tenant::EMAIL }, as: :json

    assert JSON.parse(response.body)["settled"]
    assert_equal Tenant::EMAIL, @tenant.reload.named_by
  end

  test "an account is named by whatever the tenant was configured for" do
    host! host_for(@tenant)

    post "/login", params: setup_params(named_by: Tenant::EMAIL), as: :json

    assert JSON.parse(response.body)["settled"]

    within(@tenant) do
      by_address = Actor.create!(email: "reader@example.invalid", password: PASSWORD)

      assert_nil by_address.nickname
      assert_equal "reader@example.invalid", by_address.identifier

      refused = Actor.new(nickname: "nameless", password: PASSWORD)

      refute refused.valid?
      assert_includes refused.errors.attribute_names, :email
    end
  end

  test "editing from the confirmation screen goes back with the entries kept" do
    host! host_for(@tenant)

    post "/login", params: identify_params, as: :json
    post "/login", params: { event: "setup-edit" }, as: :json
    body = JSON.parse(response.body)

    assert_equal "setup", body["prompt"]
    assert_equal "owner", body.dig("setup", "nickname")

    get "/login"

    assert_match "Continue", response.body
  end

  test "setup settles the login and signs the owner in, over JSON" do
    host! host_for(@tenant)

    post "/login", params: setup_params, as: :json
    body = JSON.parse(response.body)

    assert_response :success
    assert body["settled"]
    assert_equal "owner", body["actor"]["nickname"]

    get "/login"

    assert_redirected_to root_path
  end

  test "setup works with the bundle switched off, which is the whole point of the partials" do
    host! host_for(@tenant)

    post "/login", params: setup_params

    assert_redirected_to root_path
    assert_equal "owner", within(@tenant) { Actor.sole.nickname }
  end

  test "a refused setup re-renders the prompt rather than advancing" do
    host! host_for(@tenant)

    post "/login", params: setup_params(password: "short", password_confirmation: "short"),
         as: :json
    body = JSON.parse(response.body)

    assert_equal "setup-password", body["prompt"]
    assert_includes body["warnings"], "short-password"
    assert_equal 0, within(@tenant) { Actor.count }
  end

  test "an owner without an email is refused, because it is an owner nothing can consume" do
    host! host_for(@tenant)

    post "/login", params: setup_params(email: ""), as: :json
    body = JSON.parse(response.body)

    assert_equal "setup", body["prompt"]
    assert_includes body["warnings"], "missing-email"
    assert_equal 0, within(@tenant) { Actor.count }
  end

  test "the owner's address is recorded but not yet confirmed, because nothing confirmed it" do
    host! host_for(@tenant)

    post "/login", params: setup_params, as: :json
    assert JSON.parse(response.body)["settled"]

    actor = within(@tenant) { Actor.sole }

    assert_equal "owner@example.invalid", actor.email
    assert_nil actor.email_verified_at

    claims = within(@tenant) { actor.claims(Scopes::STANDARD, subject: actor.uuid) }

    assert_equal "owner@example.invalid", claims["email"]
    assert_equal false, claims["email_verified"]
    assert_equal "owner", claims["preferred_username"]
  end

  test "the owner the wizard created can complete the whole OIDC flow" do
    host! host_for(@tenant)

    post "/login", params: setup_params, as: :json
    assert JSON.parse(response.body)["settled"]

    registration = register(@tenant)

    authorize(client_id: registration["client_id"])
    consent! if awaiting_consent?

    granted = token(
      grant_type: "authorization_code",
      code: code_from,
      redirect_uri: OidcFlow::REDIRECT_URI,
      code_verifier: verifier,
      client_id: registration["client_id"],
      client_secret: registration["client_secret"]
    )

    claims = claims_in(granted["access_token"])

    assert_equal @tenant.uuid, claims.dig("tenant", "uuid")
    assert_equal %w[email openid profile], Scopes.list(claims["scope"])
  end

  test "setup is refused once the tenant has an owner, whatever is posted" do
    create_actor(@tenant, nickname: "first", password: PASSWORD)
    host! host_for(@tenant)

    post "/login", params: setup_params(nickname: "second"), as: :json

    assert_equal "identify", JSON.parse(response.body)["prompt"]
    assert_equal 1, within(@tenant) { Actor.count }
  end

  test "one tenant's setup does not set up another" do
    host! host_for(@tenant)
    post "/login", params: setup_params, as: :json

    reset!
    host! host_for(other_tenant)
    get "/login"

    assert_match "Continue", response.body
    assert_equal 0, within(other_tenant) { Actor.count }
  end

  test "an unknown host is still a 404 once any tenant exists" do
    host! "nobody.auth.test"

    get "/login"

    assert_response :not_found
  end

  test "the first visit to an empty deployment claims the tenant and asks to set it up" do
    with_nothing_deployed do
      host! "fresh.auth.test"

      get "/login"

      assert_response :success
      assert_match "Continue", response.body
      assert_equal "fresh", Tenant.sole.subdomain
      assert Tenant.sole.signing_key.kid.present?
    end
  end

  test "claiming is off once tenants are declared at deploy" do
    with_nothing_deployed do
      with_declared([ "declared" ]) do
        host! "fresh.auth.test"

        get "/login"

        assert_response :not_found
        refute Tenant.exists?
      end
    end
  end

  test "a host that is not a usable subdomain claims nothing" do
    with_nothing_deployed do
      host! "-nope-.auth.test"

      get "/login"

      assert_response :not_found
      refute Tenant.exists?
    end
  end

  test "only the first host claims — the second is a 404, not a second tenant" do
    with_nothing_deployed do
      host! "fresh.auth.test"
      get "/login"
      assert_response :success

      reset!
      host! "second.auth.test"
      get "/login"

      assert_response :not_found
      assert_equal 1, Tenant.count
    end
  end

  test "a declared tenant is created by the task the entrypoint runs" do
    with_nothing_deployed do
      with_declared([ "declared" ]) do
        created = Tenant.declare!

        assert_equal [ "declared" ], created.map(&:subdomain)
        assert_equal created.map(&:id), Tenant.declare!.map(&:id)
      end
    end
  end
end
