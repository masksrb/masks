require "test_helper"

class EventsTest < ActionDispatch::IntegrationTest
  setup do
    host! host_for(@tenant)

    @actor = create_actor(@tenant, nickname: "owner", email: "owner@example.com")
  end

  def events(tenant = @tenant, **conditions)
    within(tenant) { Event.where(**conditions).newest_first.to_a }
  end

  def bearer(actor: @admin)
    @client ||= create_client(
      @tenant,
      allowed_scopes: "openid profile email masks:manage",
      approved_at: Time.current,
      grant_types: [ "authorization_code", "refresh_token" ]
    )

    sign_in_as(actor)
    authorize(
      client_id: @client.client_id,
      scope: "openid masks:manage",
      resource: issuer_for(@tenant).manage_resource
    )
    consent! if awaiting_consent?

    token(
      grant_type: "authorization_code",
      code: code_from,
      redirect_uri: OidcFlow::REDIRECT_URI,
      code_verifier: verifier,
      client_id: @client.client_id
    )["access_token"]
  end

  def ask(query, token, **variables)
    post "/manage/graphql",
         params: { query: query, variables: variables }.to_json,
         headers: {
           "CONTENT_TYPE" => "application/json",
           "HTTP_AUTHORIZATION" => "Bearer #{token}"
         }

    JSON.parse(response.body)
  end

  test "signing in is recorded, with the address it came from and how it was proved" do
    sign_in_as(@actor)

    started = events(actor_id: @actor.id, action: Event::SESSION_STARTED).first

    assert_not_nil started, "a sign-in has to leave a trace"
    assert_equal [ "pwd" ], started.details["amr"]
    assert_equal @actor.id, started.by_id, "self-service is done by the subject"
    assert started.ip_address.present?
  end

  test "a wrong password is recorded against the account it was aimed at" do
    post "/login", params: { event: "identify", identifier: @actor.nickname }, as: :json
    post "/login", params: { event: "password", password: "not-the-password" }, as: :json

    refused = events(action: Event::LOGIN_REFUSED).first

    assert_not_nil refused
    assert_equal @actor.id, refused.actor_id, "a refusal names the account it went after"
    assert_nil refused.by_id, "nobody is signed in, so nobody did it"
    assert_equal "password", refused.details["factor"]
    assert_equal 0, events(action: Event::SESSION_STARTED).length
  end

  test "an identifier nobody holds is still recorded, with no subject to name" do
    post "/login", params: { event: "identify", identifier: "nobody" }, as: :json
    post "/login", params: { event: "password", password: "guessing" }, as: :json

    refused = events(action: Event::LOGIN_REFUSED).first

    assert_not_nil refused
    assert_nil refused.actor_id
    assert_equal "nobody", refused.details["identifier"]
  end

  test "changing a password is recorded, and signing out closes the pair" do
    sign_in_as(@actor)

    patch "/account/password", params: { current_password: "password", password: "a-longer-one" }
    delete "/login"

    assert_equal [ Event::SESSION_ENDED, Event::PASSWORD_CHANGED, Event::SESSION_STARTED ],
                 events(actor_id: @actor.id).map(&:action)
  end

  test "an event belongs to the tenant it happened in and no other" do
    sign_in_as(@actor)

    assert_equal 1, events(action: Event::SESSION_STARTED).length
    assert_equal 0, events(@other, action: Event::SESSION_STARTED).length

    within(@other) do
      assert_equal 0, Event.unscoped.count,
                   "the database, not the default scope, has to be what isolates the log"
    end
  end

  test "an event cannot be edited once it is written" do
    sign_in_as(@actor)

    within(@tenant) do
      held = Event.newest_first.first

      assert_raises(ActiveRecord::ReadOnlyRecord) { held.update!(action: Event::PASSWORD_CHANGED) }
    end
  end

  test "an action nobody declared is refused" do
    within(@tenant) do
      assert_raises(ActiveRecord::RecordInvalid) do
        Event.record!("something.invented", actor: @actor)
      end
    end
  end

  test "the sweep drops events past their retention and keeps the rest" do
    within(@tenant) do
      Event.record!(Event::SESSION_STARTED, actor: @actor)
      Event.insert_all!([ {
        tenant_id: @tenant.id, actor_id: @actor.id, by_id: @actor.id,
        action: Event::SESSION_ENDED, details: {},
        created_at: (Event::RETENTION + 1.day).ago
      } ])
    end

    CleanupJob.perform_now

    assert_equal [ Event::SESSION_STARTED ], events(actor_id: @actor.id).map(&:action)
  end

  test "an administrator resetting a password is named as the one who did it" do
    @admin = create_actor(@tenant, nickname: "admin", scopes: "openid profile email masks:manage")

    token = bearer
    answer = ask(<<~GQL, token, uuid: @actor.uuid)
      mutation Reset($uuid: ID!) { resetPassword(uuid: $uuid) { actor { nickname } } }
    GQL

    assert_nil answer["errors"]

    requested = events(actor_id: @actor.id, action: Event::PASSWORD_RESET_REQUESTED).first

    assert_not_nil requested
    assert_equal @admin.id, requested.by_id, "the administrator, not the subject, did this"
  end

  test "the manage API reads the log back, newest first, and filters by action" do
    @admin = create_actor(@tenant, nickname: "admin", scopes: "openid profile email masks:manage")

    token = bearer

    answer = ask(<<~GQL, token, action: Event::SESSION_STARTED)
      query Log($action: String) {
        events(action: $action) { action actor { nickname } }
        eventActions
      }
    GQL

    assert_nil answer["errors"]

    held = answer["data"]["events"]

    assert held.any?, "the administrator signed in, so there is something to read"
    assert held.all? { |event| event["action"] == Event::SESSION_STARTED }
    assert_includes answer["data"]["eventActions"], Event::PASSWORD_CHANGED
  end

  test "paging past a page boundary does not skip events sharing a timestamp" do
    @admin = create_actor(@tenant, nickname: "admin", scopes: "openid profile email masks:manage")

    at = 2.hours.ago.change(usec: 0)

    within(@tenant) do
      Event.insert_all!(
        4.times.map do
          {
            tenant_id: @tenant.id, actor_id: @actor.id, by_id: @actor.id,
            action: Event::PASSWORD_CHANGED, details: {}, created_at: at
          }
        end
      )
    end

    token = bearer

    page = ask(<<~GQL, token, action: Event::PASSWORD_CHANGED, limit: 2)
      query Log($action: String, $limit: Int) {
        events(action: $action, limit: $limit) { id }
      }
    GQL

    held = page["data"]["events"].map { |event| event["id"] }

    assert_equal 2, held.length

    rest = ask(<<~GQL, token, action: Event::PASSWORD_CHANGED, afterId: held.last, limit: 10)
      query Log($action: String, $afterId: ID, $limit: Int) {
        events(action: $action, afterId: $afterId, limit: $limit) { id }
      }
    GQL

    following = rest["data"]["events"].map { |event| event["id"] }

    assert_equal 2, following.length, "the other two share a timestamp and must not be skipped"
    assert_empty held & following, "and must not be handed back twice either"
  end

  test "an actor carries their own history" do
    sign_in_as(@actor)
    delete "/login"

    @admin = create_actor(@tenant, nickname: "admin", scopes: "openid profile email masks:manage")
    token = bearer

    answer = ask(<<~GQL, token, uuid: @actor.uuid)
      query Person($uuid: ID!) { actor(uuid: $uuid) { events { action } } }
    GQL

    assert_nil answer["errors"]
    assert_equal [ Event::SESSION_ENDED, Event::SESSION_STARTED ],
                 answer["data"]["actor"]["events"].map { |event| event["action"] }
  end
end
