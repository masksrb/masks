module Masks
  module Server
    require "test_helper"

    class RotateSigningKeysJobTest < ActiveSupport::TestCase
      def keys
        within { SigningKey.order(:created_at).to_a }
      end

      test "a new tenant rotates every 90 days without anybody choosing" do
        assert_equal 90, @tenant.key_rotation_days
        assert_equal 90, Tenant.create!(subdomain: "fresh-#{SecureRandom.hex(4)}", name: "Fresh").key_rotation_days

        travel(89.days + 1.hour) { RotateSigningKeysJob.perform_now }

        assert within { SigningKey.staged.first }, "the next key is staged a day before the active key turns 90 days old"
      end

      test "a tenant left to rotate by hand is never touched" do
        @tenant.update!(key_rotation_days: nil)
        before = keys.map(&:kid)

        travel(400.days) { RotateSigningKeysJob.perform_now }

        assert_equal before, keys.map(&:kid)
      end

      test "a scheduled tenant publishes its next key a day early, then signs with it" do
        @tenant.update!(key_rotation_days: 30)
        first = within { SigningKey.active.first }

        travel(28.days) { RotateSigningKeysJob.perform_now }
        assert_equal 0, within { SigningKey.staged.count }, "too early to stage"

        travel(29.days + 1.hour) { RotateSigningKeysJob.perform_now }
        staged = within { SigningKey.staged.first }
        assert staged, "staged a day before the key turns thirty days old"
        assert_equal first.kid, within { SigningKey.active.first.kid }

        travel(30.days + 2.hours) { RotateSigningKeysJob.perform_now }
        assert_equal staged.kid, within { SigningKey.active.first.kid }
        assert within { first.reload.retired_at.present? }
      end

      test "a schedule outside a week to a year is refused" do
        assert_raises(ActiveRecord::RecordInvalid) { @tenant.update!(key_rotation_days: 3) }
      end
    end
  end
end
