require "test_helper"
require "vips"

class AvatarsTest < ActionDispatch::IntegrationTest
  setup do
    @actor = create_actor(email: "owner@probe.example.com", name: "Ada Lovelace")
    @registration = register
    host! host_for(@tenant)
  end

  def png(width = 900, height = 300)
    Vips::Image.black(width, height)
      .add(120).cast(:uchar)
      .bandjoin([ Vips::Image.black(width, height).add(60).cast(:uchar),
                  Vips::Image.black(width, height).add(200).cast(:uchar) ])
      .copy(interpretation: :srgb)
      .pngsave_buffer
  end

  def upload(bytes = png)
    file = Tempfile.new([ "avatar", ".png" ], binmode: true)
    file.write(bytes)
    file.rewind

    Rack::Test::UploadedFile.new(file.path, "image/png")
  end

  def store!(actor = @actor)
    within(@tenant) { Avatar.store!(actor: actor, upload: png) }
  end

  def stamp(style, actor = @actor)
    within(@tenant) { Avatars.digest(actor, style) }
  end

  test "the generated styles are public and need no token" do
    %w[identicon initials].each do |style|
      get "/avatars/#{@actor.uuid}/#{style}"

      assert_response :success
      assert_equal "image/svg+xml", response.media_type
      assert_includes response.headers["Cache-Control"], "public"
      assert_equal "nosniff", response.headers["X-Content-Type-Options"]
    end
  end

  test "the initials are drawn from the name, two letters of it" do
    get "/avatars/#{@actor.uuid}/initials"

    assert_includes response.body, ">AL<"
  end

  test "the initials fall back to the nickname when there is no name" do
    bare = create_actor(nickname: "owner2", name: nil)

    get "/avatars/#{bare.uuid}/initials"

    assert_includes response.body, ">OW<"
  end

  test "an identicon is stable for an actor and differs between actors" do
    get "/avatars/#{@actor.uuid}/identicon"
    mine = response.body

    get "/avatars/#{@actor.uuid}/identicon"
    assert_equal mine, response.body

    other = create_actor(nickname: "someone")
    get "/avatars/#{other.uuid}/identicon"

    assert_not_equal mine, response.body
  end

  test "a photo is refused without a token" do
    store!

    get "/avatars/#{@actor.uuid}/photo"

    assert_response :unauthorized
    assert_includes response.headers["WWW-Authenticate"], "Bearer"
  end

  test "a photo is released to a token for that same subject" do
    store!
    granted = access_token_for(actor: @actor, registration: @registration)

    get "/avatars/#{@actor.uuid}/photo",
        headers: { "HTTP_AUTHORIZATION" => "Bearer #{granted['access_token']}" }

    assert_response :success
    assert_equal "image/webp", response.media_type
    assert_includes response.headers["Cache-Control"], "private"
  end

  test "a token for one subject cannot fetch another subject's photo" do
    other = create_actor(nickname: "someone")
    store!(other)
    granted = access_token_for(actor: @actor, registration: @registration)

    get "/avatars/#{other.uuid}/photo",
        headers: { "HTTP_AUTHORIZATION" => "Bearer #{granted['access_token']}" }

    assert_response :unauthorized
  end

  test "the bare endpoint falls back to a generated style rather than refusing" do
    store!

    get "/avatars/#{@actor.uuid}"

    assert_response :success
    assert_equal "image/svg+xml", response.media_type
  end

  test "a stamped url is immutable and a stale stamp redirects to the current one" do
    current = stamp("identicon")

    get "/avatars/#{@actor.uuid}/identicon/#{current}"

    assert_response :success
    assert_includes response.headers["Cache-Control"], "immutable"

    get "/avatars/#{@actor.uuid}/identicon/#{'0' * 16}"

    assert_redirected_to "/avatars/#{@actor.uuid}/identicon/#{current}"
  end

  test "the initials stamp changes when the name does, so a stale claim redirects" do
    before = stamp("initials")

    within(@tenant) { @actor.update!(name: "Someone Else") }

    assert_not_equal before, stamp("initials")

    get "/avatars/#{@actor.uuid}/initials/#{before}"

    assert_redirected_to "/avatars/#{@actor.uuid}/initials/#{stamp('initials')}"
  end

  test "a size outside the allowlist is clamped rather than honoured" do
    store!
    granted = access_token_for(actor: @actor, registration: @registration)

    get "/avatars/#{@actor.uuid}/photo?size=99999",
        headers: { "HTTP_AUTHORIZATION" => "Bearer #{granted['access_token']}" }

    assert_response :success
    assert_equal Avatar::STORED, Vips::Image.new_from_buffer(response.body, "").width
  end

  test "a smaller size is served at that size" do
    store!
    granted = access_token_for(actor: @actor, registration: @registration)

    get "/avatars/#{@actor.uuid}/photo?size=64",
        headers: { "HTTP_AUTHORIZATION" => "Bearer #{granted['access_token']}" }

    assert_equal 64, Vips::Image.new_from_buffer(response.body, "").width
  end

  test "an unknown style and an unknown actor are both a plain 404" do
    get "/avatars/#{@actor.uuid}/nonsense"
    assert_response :not_found

    get "/avatars/#{SecureRandom.uuid}/identicon"
    assert_response :not_found
  end

  test "an actor with no photo has none to serve" do
    get "/avatars/#{@actor.uuid}/photo",
        headers: { "HTTP_AUTHORIZATION" =>
          "Bearer #{access_token_for(actor: @actor, registration: @registration)['access_token']}" }

    assert_response :not_found
  end

  test "an offsite picture_url is handed over as a claim, never redirected to" do
    within(@tenant) { @actor.update!(picture_url: "https://example.com/me.png") }
    granted = access_token_for(actor: @actor, registration: @registration)

    get "/avatars/#{@actor.uuid}/photo",
        headers: { "HTTP_AUTHORIZATION" => "Bearer #{granted['access_token']}" }

    assert_response :not_found
  end

  test "one tenant cannot reach another tenant's actor" do
    stranger = create_actor(other_tenant, nickname: "stranger")

    get "/avatars/#{stranger.uuid}/identicon"

    assert_response :not_found
  end

  test "uploads are re-encoded to a square webp, whatever came in" do
    held = store!

    assert_equal "image/webp", held.content_type

    image = Vips::Image.new_from_buffer(held.data, "")

    assert_equal Avatar::STORED, image.width
    assert_equal Avatar::STORED, image.height
  end

  test "an svg is not an avatar" do
    assert_raises(Avatar::Unreadable) do
      within(@tenant) do
        Avatar.store!(actor: @actor, upload: %(<svg xmlns="http://www.w3.org/2000/svg"/>))
      end
    end
  end

  test "userinfo carries every avatar url and a resolved picture" do
    store!
    granted = access_token_for(actor: @actor, registration: @registration)

    get "/userinfo", headers: { "HTTP_AUTHORIZATION" => "Bearer #{granted['access_token']}" }

    claims = JSON.parse(response.body)
    avatars = claims["masks:avatars"]

    assert_equal %w[photo identicon initials], avatars.keys
    assert_equal claims["picture"], avatars["photo"]

    avatars.each_value do |url|
      assert url.start_with?(origin_for(@tenant)), "#{url} is not under the issuer"
    end
  end

  test "picture falls back to the identicon when there is no photo" do
    granted = access_token_for(actor: @actor, registration: @registration)

    get "/userinfo", headers: { "HTTP_AUTHORIZATION" => "Bearer #{granted['access_token']}" }

    claims = JSON.parse(response.body)

    assert_nil claims["masks:avatars"]["photo"]
    assert_equal claims["masks:avatars"]["identicon"], claims["picture"]
  end

  test "picture_url still wins the picture claim when the actor set one" do
    within(@tenant) { @actor.update!(picture_url: "https://example.com/me.png") }
    granted = access_token_for(actor: @actor, registration: @registration)

    get "/userinfo", headers: { "HTTP_AUTHORIZATION" => "Bearer #{granted['access_token']}" }

    claims = JSON.parse(response.body)

    assert_equal "https://example.com/me.png", claims["picture"]
    assert_nil claims["masks:avatars"]["photo"]
  end

  test "the id token carries the avatar urls, so a client needs no second request" do
    granted = access_token_for(actor: @actor, registration: @registration)
    claims = claims_in(granted["id_token"])

    assert_equal %w[photo identicon initials], claims["masks:avatars"].keys
  end

  test "discovery advertises the endpoint and what it supports" do
    get "/.well-known/openid-configuration"

    body = JSON.parse(response.body)

    assert_equal "#{origin_for(@tenant)}/avatars", body["avatar_endpoint"]
    assert_equal Avatars::STYLES, body["avatar_styles_supported"]
    assert_equal Avatars::SIZES, body["avatar_sizes_supported"]
    assert_includes body["claims_supported"], "masks:avatars"
  end

  test "an actor uploads and removes their own photo from their account page" do
    sign_in_as(@actor)

    post "/account/avatar", params: { avatar: upload }

    assert_redirected_to root_path(anchor: "avatar")
    assert within(@tenant) { Avatars.photo(@actor.reload) }.present?

    delete "/account/avatar"

    assert_nil within(@tenant) { Avatars.photo(@actor.reload) }
  end

  test "a signed-out browser cannot upload a photo for anyone" do
    post "/account/avatar", params: { avatar: upload }

    assert_response :unauthorized
  end

  test "an administrator's session sees another actor's photo, so the console can draw it" do
    subject = create_actor(nickname: "someone")
    store!(subject)
    admin = create_actor(nickname: "admin", scopes: Scopes.join(Scopes::STANDARD + [ Scopes::MANAGE ]))

    sign_in_as(admin)

    get "/avatars/#{subject.uuid}/photo"

    assert_response :success
  end

  test "an ordinary actor's session does not see another actor's photo" do
    subject = create_actor(nickname: "someone")
    store!(subject)

    sign_in_as(@actor)

    get "/avatars/#{subject.uuid}/photo"

    assert_response :unauthorized
  end

  test "an actor's own session sees their own photo without a token" do
    store!
    sign_in_as(@actor)

    get "/avatars/#{@actor.uuid}/photo"

    assert_response :success
    assert_equal "image/webp", response.media_type
  end
end
