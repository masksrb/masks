require "test_helper"

class NamespaceClaimTest < ActionDispatch::IntegrationTest
  APP = "https://demo.uris.test".freeze
  RESOURCE = "#{APP}/mcp".freeze
  RETURN_TO = "#{APP}/auth/handshake/callback".freeze
  REDIRECT_URI = "#{APP}/auth/masks/callback".freeze
  SCOPE = "openid profile email offline_access uris:".freeze

  OTHER = "https://other.uris.test".freeze
  OTHER_RESOURCE = "#{OTHER}/mcp".freeze

  setup do
    @owner = create_actor(@tenant, nickname: "owner", password: "password",
                          scopes: Scopes.join(Scopes::STANDARD + [ Scopes::MANAGE ]))
    host! host_for(@tenant)
  end

  def connect(resource: RESOURCE, origin: APP, scope: SCOPE, name: "uris")
    query = {
      client_name: name,
      resource: resource,
      scope: scope,
      return_to: "#{origin}/auth/handshake/callback",
      state: "app-state"
    }.to_a

    query << [ "redirect_uris", "#{origin}/auth/masks/callback" ]

    get "/handshake?#{URI.encode_www_form(query)}"
  end

  def approve!
    hid = response.body[/name="hid"[^>]*value="([^"]*)"/, 1]

    post "/handshake", params: { approve: "yes", hid: hid }
  end

  def claimed(name = "uris:")
    within(@tenant) { Namespace.find_by(name: name) }
  end

  test "approving a handshake claims the namespace it asks for" do
    sign_in_as(@owner)
    connect
    approve!

    within(@tenant) do
      held = Namespace.find_by(name: "uris:")

      assert_equal RESOURCE, held.resource
      assert_equal "uris", held.client.name
      assert held.claimed_at.present?
    end
  end

  test "claiming grants the namespace to whoever approved it" do
    sign_in_as(@owner)

    assert_not within(@tenant) { Actor.find(@owner.id).holds?("uris:") }

    connect
    approve!

    assert within(@tenant) { Actor.find(@owner.id).holds?("uris:") },
           "the approver must be able to use what they connected"
  end

  test "the screen says the namespace is being claimed and granted" do
    sign_in_as(@owner)
    connect

    assert_response :success
    assert_match "uris:", response.body
    assert_match "granted to you", response.body
  end

  test "another resource cannot take a namespace that is claimed" do
    sign_in_as(@owner)
    connect
    approve!

    connect(resource: OTHER_RESOURCE, origin: OTHER, name: "impostor")

    assert_response :bad_request
    assert_match "uris: is claimed by #{RESOURCE}", response.body
    assert_equal RESOURCE, claimed.resource
  end

  test "an admin refused over a claimed namespace is sent to the console that can release it" do
    sign_in_as(@owner)
    connect
    approve!

    connect(resource: OTHER_RESOURCE, origin: OTHER, name: "impostor")

    assert_response :bad_request
    assert_select "a[href=?]", manage_path, "Open the console"
  end

  test "a namespace conflict is only ever an admin's to see, because a prefix is more than anybody else holds" do
    connector = create_actor(@tenant, nickname: "connector", password: "password",
                             scopes: Scopes.join(Scopes::STANDARD + [ Scopes::HANDSHAKE, "uris:" ]))

    sign_in_as(@owner)
    connect
    approve!

    reset!
    host! host_for(@tenant)

    sign_in_as(connector)
    connect(resource: OTHER_RESOURCE, origin: OTHER, name: "impostor")

    assert_response :bad_request
    assert_match "uris: is more than this account holds", response.body
    assert_select "a[href=?]", manage_path, false
  end

  test "the same resource shaking hands again keeps its claim" do
    sign_in_as(@owner)
    connect
    approve!

    first = claimed

    connect
    approve!

    assert_response :redirect
    assert_equal first.id, claimed.id
    assert_equal RESOURCE, claimed.resource
  end

  test "a claim survives archiving the client that holds it" do
    sign_in_as(@owner)
    connect
    approve!

    within(@tenant) do
      claimed.client.update!(archived_at: Time.current)

      assert_equal RESOURCE, Namespace.find_by(name: "uris:").resource
    end
  end

  test "no application may claim the namespace masks keeps for itself" do
    within(@tenant) do
      held = Namespace.new(name: Scopes::NAMESPACE, resource: RESOURCE, claimed_at: Time.current)

      assert_not held.valid?
      assert_match "belongs to this issuer", held.errors.full_messages.join
    end
  end

  test "a namespace must end in a colon" do
    within(@tenant) do
      held = Namespace.new(name: "uris:catalog:read", resource: RESOURCE, claimed_at: Time.current)

      assert_not held.valid?
      assert_match "must end in a colon", held.errors.full_messages.join
    end
  end

  test "a token minted after the claim carries the namespace" do
    sign_in_as(@owner)
    connect
    approve!

    granted = within(@tenant) do
      Actor.find(@owner.id).permitted_scopes(%w[openid uris:catalog:read uris:settings:admin])
    end

    assert_includes granted, "uris:catalog:read"
    assert_includes granted, "uris:settings:admin"
  end
end
