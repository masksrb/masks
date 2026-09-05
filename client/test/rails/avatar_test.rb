require_relative "test_helper"

class AvatarTest < EngineIntegrationTest
  test "the session carries every avatar url and a resolved picture" do
    sign_in!

    get "/auth/session", headers: host.merge("HTTP_ACCEPT" => "application/json")

    assert_response :success
    assert_equal issuer.avatars(SUBDOMAIN), json["avatars"]
    assert_equal issuer.avatars(SUBDOMAIN)["photo"], json["picture"]
  end

  test "the proxy fetches the photo with the token the browser never sees" do
    sign_in!

    get "/auth/avatar", headers: host

    assert_response :success
    assert_equal "image/webp", response.media_type
    assert_equal TestIssuer::PHOTO, response.body
    assert_includes response.headers["Cache-Control"], "private"
  end

  test "a size travels upstream, clamped to what the issuer serves" do
    sign_in!

    get "/auth/avatar?size=48", headers: host

    assert_response :success
  end

  test "a signed-out browser gets no photo at all" do
    connect!

    get "/auth/avatar", headers: host

    assert_response :not_found
  end
end

class AvatarClaimsTest < EngineTest
  URLS = {
    "photo" => "https://auth.test/avatars/actor-1/photo/aaaa",
    "identicon" => "https://auth.test/avatars/actor-1/identicon/bbbb",
    "initials" => "https://auth.test/avatars/actor-1/initials/cccc"
  }.freeze

  def claims(**overrides)
    Masks::Client::Claims.new({ "sub" => "actor-1" }.merge(overrides))
  end

  test "the three styles are readable by name" do
    held = claims("masks:avatars" => URLS).avatars

    assert_equal URLS["photo"], held.photo
    assert_equal URLS["identicon"], held.identicon
    assert_equal URLS["initials"], held.initials
    assert_equal URLS["initials"], held["initials"]
    assert held.photo?
  end

  test "picture prefers the standard claim, then the photo, then the identicon" do
    assert_equal "https://elsewhere.test/me.png",
                 claims("picture" => "https://elsewhere.test/me.png",
                        "masks:avatars" => URLS).picture

    assert_equal URLS["photo"], claims("masks:avatars" => URLS).picture

    assert_equal URLS["identicon"],
                 claims("masks:avatars" => URLS.merge("photo" => nil)).picture
  end

  test "an issuer that says nothing about avatars is not an error" do
    held = claims.avatars

    refute held.present?
    refute held.photo?
    assert_nil claims.picture
  end

  test "the issuer builds a url for a style it advertises and refuses one it does not" do
    subject = Masks::Client.issuer(issuer.url_for(SUBDOMAIN))

    assert_equal "#{subject.url}/avatars/actor-1/identicon",
                 subject.avatar_url("actor-1")
    assert_equal "#{subject.url}/avatars/actor-1/photo?size=64",
                 subject.avatar_url("actor-1", style: "photo", size: 64)

    error = assert_raises(Masks::Client::Rejected) do
      subject.avatar_url("actor-1", style: "hologram")
    end

    assert_equal "invalid_style", error.code
  end
end
