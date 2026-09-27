module Masks
  module Server
    require "test_helper"

    class MailedLinksTest < ActiveSupport::TestCase
      setup do
        @actor = create_actor(@tenant, nickname: "sam", email: "old@example.com")
      end

      test "a reset link sent to an address the account has since left no longer works" do
        secret = within { PasswordReset.open!(actor: @actor).tap(&:delivered!).secret }

        within { @actor.update!(email: "new@example.com") }

        assert_nil within { PasswordReset.settle!(secret, "a-new-password-1") }
      end

      test "an invitation sent to an address the account has since left no longer works" do
        invited = within { Actor.create!(nickname: "new", email: "wrong@example.com") }
        secret = within { Invitation.open!(actor: invited).tap(&:delivered!).secret }

        within { invited.update!(email: "right@example.com") }

        assert_nil within { Invitation.accept!(secret, "a-new-password-1") }
      end

      test "a reset link confirms only the address it was sent to" do
        reset = within { PasswordReset.open!(actor: @actor).tap(&:delivered!) }

        within { reset.update!(payload: reset.payload.merge("email" => "elsewhere@example.com")) }
        within { PasswordReset.settle!(reset.secret, "a-new-password-1") }

        assert_nil within { @actor.reload.email_verified_at }
      end

      test "a reset link to the address still on the account confirms it" do
        secret = within { PasswordReset.open!(actor: @actor).tap(&:delivered!).secret }

        within { PasswordReset.settle!(secret, "a-new-password-1") }

        assert within { @actor.reload.email_verified_at }
      end
    end
  end
end
