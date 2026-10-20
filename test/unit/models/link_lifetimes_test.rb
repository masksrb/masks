module Masks
  module Server
    require "test_helper"

    class LinkLifetimesTest < ActiveSupport::TestCase
      setup do
        @actor = create_actor(@tenant, nickname: "sam", email: "sam@example.com")
      end

      test "a tenant starts with the usual lifetimes" do
        assert_equal 7.days, Invitation.lifetime(@tenant)
        assert_equal 14.days, Membership.lifetime(@tenant)
        assert_equal 30.minutes, PasswordReset.lifetime(@tenant)
        assert_equal 2.days, EmailVerification.lifetime(@tenant)
      end

      test "each lifetime stays within its bounds" do
        {
          invitation_lifetime: [ 59.minutes, 1.hour, 30.days, 31.days ],
          organization_invitation_lifetime: [ 59.minutes, 1.hour, 30.days, 31.days ],
          password_reset_lifetime: [ 4.minutes, 5.minutes, 1.day, 25.hours ],
          email_verification_lifetime: [ 59.minutes, 1.hour, 14.days, 15.days ]
        }.each do |attribute, (short, shortest, longest, long)|
          @tenant.reload

          @tenant[attribute] = shortest.to_i
          assert @tenant.valid?, "#{attribute} takes #{shortest.inspect}"
          @tenant[attribute] = longest.to_i
          assert @tenant.valid?, "#{attribute} takes #{longest.inspect}"

          @tenant[attribute] = short.to_i
          refute @tenant.valid?, "#{attribute} refuses #{short.inspect}"
          assert_match "must be from", @tenant.errors[attribute].first
          @tenant[attribute] = long.to_i
          refute @tenant.valid?, "#{attribute} refuses #{long.inspect}"
          @tenant[attribute] = nil
          refute @tenant.valid?, "#{attribute} refuses nothing"
        end
      end

      test "a password reset lasts as long as its tenant says" do
        @tenant.update!(password_reset_lifetime: 10.minutes.to_i)
        secret = within { PasswordReset.open!(actor: @actor).secret }

        travel 9.minutes do
          assert within { PasswordReset.redeem(secret) }
        end

        travel 11.minutes do
          assert_nil within { PasswordReset.settle!(secret, "a-new-password-1") }
        end
      end

      test "an email confirmation lasts as long as its tenant says" do
        @tenant.update!(email_verification_lifetime: 3.hours.to_i)
        secret = within { EmailVerification.open!(actor: @actor).secret }

        travel 2.hours do
          assert within { EmailVerification.redeem(secret) }
        end

        travel 4.hours do
          assert_nil within { EmailVerification.settle!(secret) }
        end
      end

      test "an invitation to an account lasts as long as its tenant says" do
        @tenant.update!(invitation_lifetime: 1.day.to_i)
        invited = within { Actor.create!(nickname: "new", email: "new@example.com") }
        secret = within { Invitation.open!(actor: invited).secret }

        travel 23.hours do
          assert within { Invitation.redeem(secret) }
        end

        travel 25.hours do
          assert_nil within { Invitation.accept!(secret, "a-new-password-1") }
        end
      end

      test "an invitation to an organization expires at its tenant's lifetime, counted from when it was sent" do
        acme = within { Organization.create!(key: "acme", name: "Acme") }
        membership = within { acme.memberships.create!(actor: @actor, role: "member", pending: true) }

        @tenant.update!(organization_invitation_lifetime: 2.days.to_i)
        within { membership.reload }

        travel 47.hours do
          refute membership.expired?
          assert within { Membership.outstanding.exists?(membership.id) }
        end

        travel 49.hours do
          assert membership.expired?
          refute within { Membership.outstanding.exists?(membership.id) }
        end
      end

      test "a link already sent keeps the lifetime it was sent with" do
        secret = within { PasswordReset.open!(actor: @actor).secret }
        @tenant.update!(password_reset_lifetime: 5.minutes.to_i)

        travel 20.minutes do
          assert within { PasswordReset.redeem(secret) }
        end
      end

      test "one tenant's lifetime leaves another's alone" do
        other = Tenant.create!(subdomain: "other-#{SecureRandom.hex(4)}", name: "Other")
        other.update!(password_reset_lifetime: 5.minutes.to_i)

        reset = within { PasswordReset.open!(actor: @actor) }

        assert_in_delta 30.minutes.from_now, reset.expires_at, 5
        assert_equal 5.minutes, PasswordReset.lifetime(other)
      end

      test "outside any tenant a link gets the usual lifetime" do
        assert_equal 30.minutes, PasswordReset.lifetime(nil)
        assert_equal 7.days, Invitation.lifetime(nil)
      end
    end
  end
end
