require "test_helper"

class InvitationTest < ActionDispatch::IntegrationTest
  setup do
    host! host_for(@tenant)

    @owner = create_actor(@tenant, scopes: "openid profile email masks:manage")
  end

  def invite(nickname: "sam", email: "sam@example.com")
    within(@tenant) do
      actor = Actor.invite!(nickname: nickname, email: email)
      [ actor, Invitation.open!(actor: actor, invited_by: @owner) ]
    end
  end

  test "an invited actor cannot sign in until the invitation is accepted" do
    actor, _invitation = invite

    within(@tenant) do
      assert_not actor.activated?
      assert_nil Actor.authenticate("sam", "")
      assert_nil Actor.authenticate("sam", "password")
    end
  end

  test "the link puts the invitation in front of the person who opened it" do
    _actor, invitation = invite

    get "/invite/#{invitation.secret}"
    assert_redirected_to login_path

    get login_path
    assert_response :success
    assert_select "form#accept-invitation"
    assert_select "input[value=sam][readonly]"
  end

  test "accepting sets a password, activates the account, and signs them in" do
    actor, invitation = invite

    get "/invite/#{invitation.secret}"
    post "/login", params: { event: "accept-invitation", password: "a-good-password" }, as: :json

    body = JSON.parse(response.body)

    assert_equal "settled", body["prompt"]
    assert_equal "sam", body.dig("actor", "nickname")

    within(@tenant) do
      assert actor.reload.activated?
      assert_equal actor, Actor.authenticate("sam", "a-good-password")
    end
  end

  test "a short password is refused and the invitation survives it" do
    _actor, invitation = invite

    get "/invite/#{invitation.secret}"
    post "/login", params: { event: "accept-invitation", password: "short" }, as: :json

    body = JSON.parse(response.body)

    assert_equal "accept-invitation", body["prompt"]
    assert_includes body["warnings"], "short-password"

    within(@tenant) { assert invitation.reload.live? }
  end

  test "an invitation works once" do
    _actor, invitation = invite

    get "/invite/#{invitation.secret}"
    post "/login", params: { event: "accept-invitation", password: "a-good-password" }, as: :json
    assert_equal "settled", JSON.parse(response.body)["prompt"]

    get "/invite/#{invitation.secret}"
    assert_response :gone
  end

  test "an expired invitation is refused at the link, not at the password" do
    _actor, invitation = invite

    within(@tenant) { invitation.update!(expires_at: 1.second.ago) }

    get "/invite/#{invitation.secret}"
    assert_response :gone
  end

  test "opening a second invitation retires the first" do
    actor, first = invite

    second = within(@tenant) { Invitation.open!(actor: actor, invited_by: @owner) }

    within(@tenant) do
      assert_not first.reload.live?
      assert second.reload.live?
    end

    get "/invite/#{first.secret}"
    assert_response :gone
  end

  test "an invitation cannot be opened for someone who already accepted" do
    within(@tenant) do
      assert_raises(Invitation::Refused) { Invitation.open!(actor: @owner) }
    end
  end

  test "a copied link does not verify the email, and a mailed one does" do
    actor, copied = invite

    within(@tenant) do
      assert_not copied.delivered?
      Invitation.accept!(copied.secret, "a-good-password")
      assert_not actor.reload.email_verified_at.present?
    end

    later, invitation = invite(nickname: "kim", email: "kim@example.com")

    within(@tenant) do
      invitation.delivered!
      Invitation.accept!(invitation.secret, "a-good-password")
      assert later.reload.email_verified_at.present?
    end
  end

  test "the invitation belongs to its tenant and no other" do
    _actor, invitation = invite

    host! host_for(@other)
    get "/invite/#{invitation.secret}"

    assert_response :gone
  end
end
