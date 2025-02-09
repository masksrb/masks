require "test_helper"

class CleanupJobTest < MasksTestCase
  test "sessions can be cleaned up" do
    Masks.installation.modify(sessions: { lifetime: "1 year" })

    s1 = make_session
    s2 =
      make_session.tap do |s|
        s.updated_at = 366.days.ago
        s.save!
      end

    assert_equal 1, Masks::SessionRecord.cleanable.count

    Masks::CleanupJob.perform_now("Masks::SessionRecord")

    assert_raises ActiveRecord::RecordNotFound do
      s2.reload
    end

    s1.reload
  end

  test "devices can be cleaned up" do
    Masks.installation.modify(devices: { lifetime: "1 year" })

    d1 = make_device
    d2 =
      make_device.tap do |d|
        d.updated_at = 366.days.ago
        d.save!
      end

    assert_equal 1, Masks::Device.cleanable.count

    Masks::CleanupJob.perform_now("Masks::Device")

    assert_raises ActiveRecord::RecordNotFound do
      d2.reload
    end

    d1.reload
  end

  test "actors can be cleaned up" do
    Masks.installation.modify(actors: { inactive: "1 year" })

    a1 = make_actor
    a2 =
      make_actor.tap do |a|
        a.last_login_at = 366.days.ago
        a.save!
      end

    assert_equal 1, Masks::Actor.cleanable.count

    Masks::CleanupJob.perform_now("Masks::Actor")

    assert_raises ActiveRecord::RecordNotFound do
      a2.reload
    end

    a1.reload
  end

  test "id tokens can be cleaned up" do
    t1 = make_id_token
    t2 =
      make_id_token.tap do |record|
        record.expires_at = 1.minute.ago
        record.save!
      end

    Masks::CleanupJob.perform_now("Masks::IdToken")

    assert_raises ActiveRecord::RecordNotFound do
      t2.reload
    end

    t1.reload
  end

  test "auth codes can be cleaned up" do
    t1 = make_auth_code
    t2 =
      make_auth_code.tap do |record|
        record.expires_at = 1.minute.ago
        record.save!
      end

    Masks::CleanupJob.perform_now("Masks::AuthorizationCode")

    assert_raises ActiveRecord::RecordNotFound do
      t2.reload
    end

    t1.reload
  end

  test "access tokens can be cleaned up" do
    t1 = make_access_token
    t2 =
      make_access_token.tap do |record|
        record.expires_at = 1.minute.ago
        record.save!
      end

    Masks::CleanupJob.perform_now("Masks::AccessToken")

    assert_raises ActiveRecord::RecordNotFound do
      t2.reload
    end

    t1.reload
  end
end
