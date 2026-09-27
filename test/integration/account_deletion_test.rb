module Masks
  module Server
    require "test_helper"

    class AccountDeletionTest < ActionDispatch::IntegrationTest
      setup do
        host! host_for(@tenant)

        @actor = create_actor(@tenant, nickname: "leaving")
        create_actor(@tenant, nickname: "boss", scopes: "openid masks:manage")
      end

      test "a person deletes their own account by typing its name" do
        sign_in_as(@actor)

        delete "/account", params: { confirm: "leaving" }

        assert_redirected_to login_path
        assert_equal "Your account was deleted.", flash[:notice]

        within do
          assert_not Actor.exists?(@actor.id)
          event = Event.where(action: Event::ACTOR_DELETED).sole
          assert_equal "leaving", event.details["identifier"]
          assert_equal "account", event.details["reason"]
        end

        get "/"
        assert_redirected_to login_path
      end

      test "the wrong name deletes nothing" do
        sign_in_as(@actor)

        delete "/account", params: { confirm: "someone" }

        assert_redirected_to "#{root_path}#delete"
        within { assert Actor.exists?(@actor.id) }
      end

      test "a sign-in older than fifteen minutes is asked to sign in again first" do
        sign_in_as(@actor)

        travel 16.minutes do
          delete "/account", params: { confirm: "leaving" }

          assert_redirected_to login_path(return_to: "#{root_path}#delete")
          within do
            assert Actor.exists?(@actor.id)
            assert_empty Session.live.where(actor_id: @actor.id).to_a
          end
        end
      end

      test "the last manager cannot delete their own account" do
        within { Actor.find_by(nickname: "boss").destroy! }
        manager = create_actor(@tenant, nickname: "last", scopes: "openid masks:manage")

        sign_in_as(manager)
        delete "/account", params: { confirm: "last" }

        assert_redirected_to "#{root_path}#delete"
        within { assert Actor.exists?(manager.id) }
      end

      test "an account a provider provisions is left to that provider" do
        within { @actor.update!(external_id: "okta-1") }

        sign_in_as(@actor)
        delete "/account", params: { confirm: "leaving" }

        within { assert Actor.exists?(@actor.id) }
      end

      test "an account an organization's directory provisions is left to that directory" do
        within do
          acme = Organization.create!(key: "acme", name: "Acme")
          acme.memberships.create!(actor: @actor, role: "member", provisioned: true, external_id: "okta-1")
        end

        sign_in_as(@actor)
        delete "/account", params: { confirm: "leaving" }

        within { assert Actor.exists?(@actor.id) }
      end

      test "signing out is not somebody else's business to delete" do
        delete "/account", params: { confirm: "leaving" }

        assert_redirected_to login_path
        within { assert Actor.exists?(@actor.id) }
      end

      test "the account page offers deletion" do
        sign_in_as(@actor)
        get "/"

        assert_select "#delete form#delete-account input[name=confirm]"
      end
    end
  end
end
