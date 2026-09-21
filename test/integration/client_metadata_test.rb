require "test_helper"
require "vips"

class ClientMetadataTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  LOGO = "https://probe.example.com/logo.png".freeze

  setup do
    @actor = create_actor(email: "owner@probe.example.com")
    host! host_for(@tenant)
  end

  def png(width = 300, height = 200)
    Vips::Image.black(width, height).add(120).cast(:uchar).pngsave_buffer
  end

  def serve_logo(body = png, status: 200)
    stub_request(:get, LOGO).to_return(status: status, body: body, headers: { "Content-Type" => "image/png" })
  end

  def registered(**metadata)
    held = nil
    perform_enqueued_jobs { held = register(@tenant, **metadata) }
    held
  end

  def client_for(registration)
    within(@tenant) { Client.find_by!(client_id: registration["client_id"]) }
  end

  def approve!(registration)
    within(@tenant) { client_for(registration).update!(approved_at: Time.current, approved_by: @actor) }
  end

  def consent_screen(registration)
    sign_in_as(@actor)
    authorize(client_id: registration["client_id"])

    auth_data
  end

  test "a registration is refused a link that is not an http URL" do
    %w[javascript:alert(1) data:text/html,hi ftp://probe.example.com/terms /terms].each do |link|
      body = register(@tenant, tos_uri: link)

      assert_equal "invalid_client_metadata", body["error"], link
    end
  end

  test "a registration is refused a link that carries credentials" do
    body = register(@tenant, policy_uri: "https://someone:secret@probe.example.com/privacy")

    assert_equal "invalid_client_metadata", body["error"]
  end

  test "a logo is fetched, squared and kept by masks, not linked to" do
    serve_logo

    client = client_for(registered(logo_uri: LOGO))
    logo = within(@tenant) { client.reload.logo }

    assert logo
    assert_equal "image/webp", logo.content_type

    image = Vips::Image.new_from_buffer(logo.data, "")

    assert_equal [ ClientLogo::STORED, ClientLogo::STORED ], [ image.width, image.height ]
  end

  test "a self-registered client's logo is shown to nobody until it is approved" do
    serve_logo
    registration = registered(logo_uri: LOGO, tos_uri: "https://probe.example.com/terms")

    shown = consent_screen(registration)

    assert_nil shown.dig("client", "logo")
    assert_equal "https://probe.example.com/terms", shown.dig("client", "terms")

    get "/clients/#{registration['client_id']}/logo"

    assert_response :not_found
  end

  test "an approved client's logo, links and return address are on the consent screen" do
    serve_logo
    registration = registered(logo_uri: LOGO, client_uri: "https://probe.example.com",
                              policy_uri: "https://probe.example.com/privacy")
    approve!(registration)

    shown = consent_screen(registration)

    assert awaiting_consent?
    assert_match %r{/clients/#{registration['client_id']}/logo\?v=\h{16}\z}, shown.dig("client", "logo")
    assert_equal "https://probe.example.com", shown.dig("client", "site")
    assert_equal "https://probe.example.com/privacy", shown.dig("client", "privacy")
    assert_equal URI.parse(REDIRECT_URI).host, shown.dig("client", "returnsTo")
  end

  test "a logo is served sealed, and cached for good only at its own digest" do
    serve_logo
    registration = registered(logo_uri: LOGO)
    approve!(registration)
    digest = within(@tenant) { client_for(registration).logo.digest }

    get "/clients/#{registration['client_id']}/logo?v=#{digest}&size=64"

    assert_response :success
    assert_equal "image/webp", response.media_type
    assert_equal "nosniff", response.headers["X-Content-Type-Options"]
    assert_equal ServesPictures::SEALED, response.headers["Content-Security-Policy"]
    assert_includes response.headers["Cache-Control"], "immutable"
    assert_equal 64, Vips::Image.new_from_buffer(response.body, "").width

    get "/clients/#{registration['client_id']}/logo"

    refute_includes response.headers["Cache-Control"], "immutable"
  end

  test "something that is not an image is refused, and the refusal is recorded" do
    serve_logo("<svg onload=alert(1)></svg>")

    client = client_for(registered(logo_uri: LOGO))

    assert_nil within(@tenant) { client.reload.logo }
    assert within(@tenant) { Event.exists?(action: Event::CLIENT_LOGO_REFUSED, client_id: client.id) }
  end

  test "a logo that cannot be reached leaves no logo" do
    serve_logo(status: 404)

    client = client_for(registered(logo_uri: LOGO))

    assert_nil within(@tenant) { client.reload.logo }
  end

  test "clearing the logo URL removes the logo" do
    serve_logo
    client = client_for(registered(logo_uri: LOGO))

    perform_enqueued_jobs { within(@tenant) { client.update!(logo_uri: nil) } }

    assert_nil within(@tenant) { client.reload.logo }
  end
end
