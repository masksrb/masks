require "test_helper"

class ThemesTest < ActionDispatch::IntegrationTest
  setup do
    @root = Pathname(Dir.mktmpdir("themes"))
    @held = Rails.configuration.masks.themes_path
    Rails.configuration.masks.themes_path = @root.to_s
    host! host_for(@tenant)
  end

  teardown do
    Rails.configuration.masks.themes_path = @held
    Themes.reload!
    FileUtils.remove_entry(@root)
  end

  def write(relative, body)
    @root.join(relative).dirname.mkpath
    @root.join(relative).write(body)
    Themes.reload!
  end

  def linked_themes
    response.body.scan(%r{<link rel="stylesheet" href="(/themes/[0-9a-f]{32}\.css)"}).flatten
  end

  test "a sign-in page links no theme when the tenant has none" do
    get "/login"

    assert_response :success
    assert_empty linked_themes
  end

  test "the tenant's theme is linked on the sign-in page and served as CSS" do
    write("#{@tenant.subdomain}.css", ".auth-page { --ground: #123456; }")

    get "/login"
    assert_equal 1, linked_themes.size

    get linked_themes.first
    assert_response :success
    assert_equal "text/css", response.media_type
    assert_includes response.body, "#123456"
    assert_equal "nosniff", response.headers["X-Content-Type-Options"]
    assert_includes response.headers["Cache-Control"], "immutable"
  end

  test "a client's theme layers after the tenant's while signing in to that client" do
    client = create_client(allowed_scopes: Scopes.join(Scopes::STANDARD))
    write("#{@tenant.subdomain}.css", ".auth-page { --ground: #111111; }")
    write("#{@tenant.subdomain}/#{client.client_id}.css", ".auth-page { --ground: #222222; }")

    authorize(client_id: client.client_id)

    assert awaiting_login?
    tenant_theme, client_theme = linked_themes
    assert_equal 2, linked_themes.size

    get tenant_theme
    assert_includes response.body, "#111111"

    get client_theme
    assert_includes response.body, "#222222"
  end

  test "another client's theme stays off the page" do
    client = create_client(allowed_scopes: Scopes.join(Scopes::STANDARD))
    write("#{@tenant.subdomain}/#{SecureRandom.uuid}.css", ".auth-page { --ground: #333333; }")

    authorize(client_id: client.client_id)

    assert awaiting_login?
    assert_empty linked_themes
  end

  test "a tenant cannot load another tenant's theme" do
    write("#{other_tenant.subdomain}.css", ".auth-page { --ground: #444444; }")
    digest = Themes.catalog.fetch(other_tenant.subdomain).digest

    get "/themes/#{digest}.css"

    assert_response :not_found
  end

  test "a theme over the size limit is not served" do
    write("#{@tenant.subdomain}.css", "a{}" * (Themes::LIMIT / 3 + 1))

    get "/login"

    assert_empty linked_themes
  end

  test "a theme leaves the page's content security policy as it was" do
    write("#{@tenant.subdomain}.css", ".auth-page { --ground: #555555; }")

    get "/login"
    policy = response.headers["Content-Security-Policy"]

    assert_includes policy, "img-src 'self' data:"
    assert_includes policy, "font-src 'self' data:"
  end
end
