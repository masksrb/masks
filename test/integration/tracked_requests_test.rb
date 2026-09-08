require "test_helper"

class TrackedRequestsTest < ActionDispatch::IntegrationTest
  OTHER_URI = "https://other.example.com/cb".freeze

  setup do
    @actor = create_actor(email: "owner@probe.example.com", name: "Owner")
    @probe = register
    @other = register(client_name: "Other", redirect_uris: [ OTHER_URI ])
    host! host_for(@tenant)
  end

  def authorize_other
    get "/authorize?#{URI.encode_www_form(
      response_type: 'code', client_id: @other['client_id'], redirect_uri: OTHER_URI,
      scope: 'openid profile email', code_challenge: challenge, code_challenge_method: 'S256'
    )}"
  end

  test "approving the screen that was rendered consents to that client, not the newer one" do
    sign_in_as(@actor)

    authorize(client_id: @probe["client_id"])
    assert awaiting_consent?
    probe_rid = current_rid

    authorize_other
    assert awaiting_consent?
    refute_equal probe_rid, current_rid

    post "/login", params: { event: "consent", approve: "yes", rid: probe_rid }
    follow_redirect! while response.redirect? && URI.parse(response.location).host.to_s.end_with?(".auth.test")

    assert response.location.start_with?(OidcFlow::REDIRECT_URI), "answered the wrong client"

    consented = within { Consent.live.map { |record| record.client.client_id } }

    assert_equal [ @probe["client_id"] ], consented
  end

  test "two authorize requests in one browser each complete on their own terms" do
    sign_in_as(@actor)

    authorize(client_id: @probe["client_id"])
    probe_rid = current_rid

    authorize_other
    other_rid = current_rid

    post "/login", params: { event: "consent", approve: "yes", rid: other_rid }
    follow_redirect! while response.redirect? && URI.parse(response.location).host.to_s.end_with?(".auth.test")

    assert response.location.start_with?(OTHER_URI)
    other_code = code_from

    post "/login", params: { event: "consent", approve: "yes", rid: probe_rid }
    follow_redirect! while response.redirect? && URI.parse(response.location).host.to_s.end_with?(".auth.test")

    assert response.location.start_with?(OidcFlow::REDIRECT_URI)
    probe_code = code_from

    assert probe_code.present?
    assert_not_equal probe_code, other_code
  end

  test "a rid from another browser drives nothing and answers nothing" do
    sign_in_as(@actor)
    authorize(client_id: @probe["client_id"])

    stolen = current_rid
    pending = within { PendingRequest.redeem(stolen) }

    assert pending.present?

    reset!
    host! host_for(@tenant)
    sign_in_as(@actor)

    post "/login", params: { event: "consent", approve: "yes", rid: stolen }

    assert_not within { PendingRequest.find(pending.id).consumed? }
    assert_equal 0, within { AuthorizationCode.count }
    assert_equal 0, within { Consent.live.count }
  end

  test "a rid that was never issued is ignored rather than obeyed" do
    sign_in_as(@actor)
    authorize(client_id: @probe["client_id"])

    post "/login", params: { event: "consent", approve: "yes", rid: SecureRandom.urlsafe_base64(48) }

    assert_equal 0, within { AuthorizationCode.count }
    assert_equal 0, within { Consent.live.count }
  end

  test "an expired request cannot be resumed" do
    sign_in_as(@actor)
    authorize(client_id: @probe["client_id"])

    rid = current_rid
    within { PendingRequest.redeem(rid).update!(expires_at: 1.second.ago) }

    post "/login", params: { event: "consent", approve: "yes", rid: rid }

    assert_equal 0, within { AuthorizationCode.count }
  end

  test "the oldest tracked request is evicted once the cookie has held enough of them" do
    sign_in_as(@actor)

    authorize(client_id: @probe["client_id"], state: "first")
    first = current_rid

    ApplicationController::TRACKED.times do |index|
      authorize(client_id: @probe["client_id"], state: "filler-#{index}")
    end

    post "/login", params: { event: "consent", approve: "yes", rid: first }

    assert_equal 0, within { AuthorizationCode.count }
  end

  test "a request is opened once however many times the same authorize arrives" do
    sign_in_as(@actor)

    3.times { authorize(client_id: @probe["client_id"]) }

    assert_equal 1, within { PendingRequest.count }
  end
end
