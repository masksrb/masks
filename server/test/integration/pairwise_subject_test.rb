require "test_helper"

class PairwiseSubjectTest < ActionDispatch::IntegrationTest
  SECTOR_URI = "https://sectors.example.com/redirects.json".freeze
  OTHER_URI = "https://probe.example.net/cb".freeze

  setup do
    @actor = create_actor(email: "owner@example.com")
    host! host_for(@tenant)
  end

  test "a public client still sees the actor's own identifier" do
    registration = register(@tenant)
    granted = access_token_for(actor: @actor, registration: registration)

    assert_equal @actor.uuid, claims_in(granted["id_token"])["sub"]
    assert_equal @actor.uuid, claims_in(granted["access_token"])["sub"]
  end

  test "a pairwise client sees a subject of its own, and never the actor's" do
    registration = register(@tenant, subject_type: "pairwise")

    assert_equal "pairwise", registration["subject_type"]

    granted = access_token_for(actor: @actor, registration: registration)
    held = claims_in(granted["id_token"])["sub"]

    assert_not_equal @actor.uuid, held
    assert_equal held, claims_in(granted["access_token"])["sub"]
    assert_equal held, within { Subject.find_by(actor_id: @actor.id)&.sub }
  end

  test "the same person is two different subjects to two pairwise sectors" do
    here = register(@tenant, subject_type: "pairwise")
    there = register(
      @tenant,
      subject_type: "pairwise",
      redirect_uris: [ OTHER_URI ]
    )

    first = claims_in(access_token_for(actor: @actor, registration: here)["id_token"])["sub"]

    @verifier = nil

    second = within do
      client = Client.find_by(client_id: there["client_id"])

      Subjects.for(@actor, client)
    end

    assert_not_equal first, second
  end

  test "two pairwise clients on one host share the sector, and so the subject" do
    here = register(@tenant, subject_type: "pairwise")
    there = register(@tenant, subject_type: "pairwise", client_name: "Second")

    first, second = within do
      [ here, there ].map do |held|
        Subjects.for(@actor, Client.find_by(client_id: held["client_id"]))
      end
    end

    assert_equal first, second
  end

  test "a pairwise subject holds steady across sign-ins" do
    registration = register(@tenant, subject_type: "pairwise")

    first = claims_in(access_token_for(actor: @actor, registration: registration)["id_token"])["sub"]

    @verifier = nil

    second = claims_in(access_token_for(actor: @actor, registration: registration)["id_token"])["sub"]

    assert_equal first, second
  end

  test "userinfo answers with the same pairwise subject the id token carried" do
    registration = register(@tenant, subject_type: "pairwise")
    granted = access_token_for(actor: @actor, registration: registration)

    get "/userinfo", headers: { "Authorization" => "Bearer #{granted['access_token']}" }

    assert_response :success
    assert_equal claims_in(granted["id_token"])["sub"], JSON.parse(response.body)["sub"]
  end

  test "the avatar a pairwise client is told about carries no public identifier" do
    registration = register(@tenant, subject_type: "pairwise")
    granted = access_token_for(actor: @actor, registration: registration)
    held = claims_in(granted["id_token"])
    urls = held[Actor::AVATARS_CLAIM].values.compact

    assert urls.any?
    assert urls.none? { |url| url.include?(@actor.uuid) }, "an avatar URL named the actor"
    assert urls.all? { |url| url.include?(held["sub"]) }
  end

  test "an avatar is still served when it is asked for by a pairwise subject" do
    registration = register(@tenant, subject_type: "pairwise")
    granted = access_token_for(actor: @actor, registration: registration)
    url = claims_in(granted["id_token"])[Actor::AVATARS_CLAIM][Avatars::IDENTICON]

    get URI.parse(url).path

    assert_response :success
  end

  test "introspection describes a token by the subject its client knows" do
    registration = register(@tenant, subject_type: "pairwise")
    granted = access_token_for(actor: @actor, registration: registration)

    post "/introspect",
         params: { token: granted["access_token"] },
         headers: {
           "Authorization" => ActionController::HttpAuthentication::Basic.encode_credentials(
             registration["client_id"], registration["client_secret"]
           )
         }

    assert_response :success
    assert_equal claims_in(granted["id_token"])["sub"], JSON.parse(response.body)["sub"]
  end

  test "a logout token names the subject its client was told about" do
    registration = register(@tenant, subject_type: "pairwise")
    granted = access_token_for(actor: @actor, registration: registration)
    held = claims_in(granted["id_token"])["sub"]

    client, session = within { [ Client.find_by(client_id: registration["client_id"]), Session.live.first ] }
    token = within { issuer_for(@tenant).logout_token(client: client, subject: Subjects.for(@actor, client), sid: session.uuid) }

    assert_equal held, claims_in(token)["sub"]
  end

  test "a pairwise client whose redirect URIs span hosts needs a sector to point at" do
    body = register(
      @tenant,
      subject_type: "pairwise",
      redirect_uris: [ OidcFlow::REDIRECT_URI, OTHER_URI ]
    )

    assert_equal "invalid_client_metadata", body["error"]
    assert_match(/sector/i, body["error_description"])
  end

  test "a sector identifier is only taken once the document at it names the redirect URIs" do
    stub_request(:get, SECTOR_URI).to_return(
      status: 200,
      body: [ OidcFlow::REDIRECT_URI, OTHER_URI ].to_json
    )

    body = register(
      @tenant,
      subject_type: "pairwise",
      sector_identifier_uri: SECTOR_URI,
      redirect_uris: [ OidcFlow::REDIRECT_URI, OTHER_URI ]
    )

    assert_equal SECTOR_URI, body["sector_identifier_uri"]
    assert_equal "pairwise", body["subject_type"]
  end

  test "a sector identifier that leaves out a redirect URI is refused" do
    stub_request(:get, SECTOR_URI).to_return(
      status: 200,
      body: [ OidcFlow::REDIRECT_URI ].to_json
    )

    body = register(
      @tenant,
      subject_type: "pairwise",
      sector_identifier_uri: SECTOR_URI,
      redirect_uris: [ OidcFlow::REDIRECT_URI, OTHER_URI ]
    )

    assert_equal "invalid_client_metadata", body["error"]
    assert_match(/does not list/, body["error_description"])
  end

  test "clients sharing a sector identifier share the subject, whatever they redirect to" do
    stub_request(:get, SECTOR_URI).to_return(
      status: 200,
      body: [ OidcFlow::REDIRECT_URI, OTHER_URI ].to_json
    )

    here = register(
      @tenant,
      subject_type: "pairwise",
      sector_identifier_uri: SECTOR_URI,
      redirect_uris: [ OidcFlow::REDIRECT_URI ]
    )

    there = register(
      @tenant,
      subject_type: "pairwise",
      sector_identifier_uri: SECTOR_URI,
      redirect_uris: [ OTHER_URI ]
    )

    first, second = within do
      [ here, there ].map do |held|
        Subjects.for(@actor, Client.find_by(client_id: held["client_id"]))
      end
    end

    assert_equal first, second
  end

  test "a sector identifier has to be https" do
    body = register(
      @tenant,
      subject_type: "pairwise",
      sector_identifier_uri: "http://sectors.example.com/redirects.json"
    )

    assert_equal "invalid_client_metadata", body["error"]
    assert_match(/https/, body["error_description"])
  end

  test "a subject a pairwise client is given belongs to nobody in another tenant" do
    registration = register(@tenant, subject_type: "pairwise")
    held = within { Subjects.for(@actor, Client.find_by(client_id: registration["client_id"])) }

    assert_nil within(@other) { Subjects.locate(held) }
    assert_equal @actor.id, within { Subjects.locate(held).id }
  end

  test "the server says which subject types it will issue" do
    get "/.well-known/openid-configuration"

    assert_equal %w[public pairwise], JSON.parse(response.body)["subject_types_supported"]
  end

  test "an unknown subject type is refused" do
    body = register(@tenant, subject_type: "sideways")

    assert_equal "invalid_client_metadata", body["error"]
    assert_match(/subject type/i, body["error_description"])
  end
end
