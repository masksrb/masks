require "test_helper"

class NoJavascriptTest < ActionDispatch::IntegrationTest
  setup do
    @actor = create_actor(email: "owner@probe.example.com", name: "Owner")
    @registration = register
    host! host_for(@tenant)
  end

  def assert_forms_carry_the_rid(prompt)
    assert_equal prompt, auth_data["prompt"]
    assert_operator login_forms.size, :>, 0, "#{prompt} rendered no form posting to /login"

    rids = form_rids

    assert_empty rids.compact_blank.reject { |rid| rid == current_rid },
                 "#{prompt} rendered a rid that is not the one this request is for"
    assert_empty rids.select(&:blank?),
                 "#{prompt} rendered #{rids.count(&:blank?)} of #{rids.size} forms without a rid"
  end

  test "every form on the way through an authorize carries the rid it was rendered for" do
    totp = enable_otp(@actor)
    within { @actor.generate_backup_codes! }

    authorize(client_id: @registration["client_id"])
    assert_forms_carry_the_rid "identify"

    submit(event: "identify", identifier: @actor.nickname)
    assert_forms_carry_the_rid "first-factor"

    submit(event: "password", password: "password")
    assert_forms_carry_the_rid "second-factor"

    submit(event: "use-backup-code")
    assert_forms_carry_the_rid "backup-code"

    submit(event: "use-authenticator")
    submit(event: "otp", code: totp.now)
    assert_forms_carry_the_rid "consent"

    submit(event: "consent", approve: "yes")

    assert_equal OidcFlow::REDIRECT_URI, response.location.split("?").first
    assert code_from.present?
  end

  test "a browser with no javascript signs in using only what the forms carry" do
    authorize(client_id: @registration["client_id"], state: "no-js")

    submit(event: "identify", identifier: @actor.nickname)
    submit(event: "password", password: "password")
    submit(event: "consent", approve: "yes")

    assert_equal "no-js", redirected["state"]
    assert redirected["code"].present?
  end

  test "the referrer policy still lets a browser send an origin when it posts a form" do
    authorize(client_id: @registration["client_id"])

    assert_equal "same-origin", response.headers["Referrer-Policy"],
                 "no-referrer makes browsers send Origin: null, which fails forgery protection"
  end

  private

    def submit(event:, **updates)
      post "/login", params: { event: event, rid: form_rids.compact_blank.first, **updates }
      follow_redirect! while response.redirect? && URI.parse(response.location).host.to_s.end_with?(".auth.test")
      response
    end
end
