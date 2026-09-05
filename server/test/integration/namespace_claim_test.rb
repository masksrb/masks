require "test_helper"

class NamespaceClaimTest < ActionDispatch::IntegrationTest
  APP = "https://jons.things.test".freeze
  RESOURCE = "#{APP}/mcp".freeze
  RETURN_TO = "#{APP}/auth/handshake/callback".freeze
  REDIRECT_URI = "#{APP}/auth/masks/callback".freeze
  SCOPE = "openid profile email offline_access things:".freeze

  OTHER = "https://other.things.test".freeze
  OTHER_RESOURCE = "#{OTHER}/mcp".freeze

  setup do
    @owner = create_actor(@tenant, nickname: "owner", password: "password",
                          scopes: Scopes.join(Scopes::STANDARD + [ Scopes::MANAGE ]))
    host! host_for(@tenant)
  end

  def connect(resource: RESOURCE, origin: APP, scope: SCOPE, name: "things")
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

  def claimed(name = "things:")
    within(@tenant) { Namespace.find_by(name: name) }
  end

  test "approving a handshake claims the namespace it asks for" do
    sign_in_as(@owner)
    connect
    approve!

    within(@tenant) do
      held = Namespace.find_by(name: "things:")

      assert_equal RESOURCE, held.resource
      assert_equal "things", held.client.name
      assert held.claimed_at.present?
    end
  end

  test "claiming grants the namespace to whoever approved it" do
    sign_in_as(@owner)

    assert_not within(@tenant) { Actor.find(@owner.id).holds?("things:") }

    connect
    approve!

    assert within(@tenant) { Actor.find(@owner.id).holds?("things:") },
           "the approver must be able to use what they connected"
  end

  test "the screen says the namespace is being claimed and granted" do
    sign_in_as(@owner)
    connect

    assert_response :success
    assert_match "things:", response.body
    assert_match "granted to you", response.body
  end

  test "another resource cannot take a namespace that is claimed" do
    sign_in_as(@owner)
    connect
    approve!

    connect(resource: OTHER_RESOURCE, origin: OTHER, name: "impostor")

    assert_response :bad_request
    assert_match "things: is claimed by #{RESOURCE}", response.body
    assert_equal RESOURCE, claimed.resource
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

      assert_equal RESOURCE, Namespace.find_by(name: "things:").resource
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
      held = Namespace.new(name: "things:catalog:read", resource: RESOURCE, claimed_at: Time.current)

      assert_not held.valid?
      assert_match "must end in a colon", held.errors.full_messages.join
    end
  end

  test "a token minted after the claim carries the namespace" do
    sign_in_as(@owner)
    connect
    approve!

    granted = within(@tenant) do
      Actor.find(@owner.id).permitted_scopes(%w[openid things:catalog:read things:settings:admin])
    end

    assert_includes granted, "things:catalog:read"
    assert_includes granted, "things:settings:admin"
  end
end
