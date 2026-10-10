module Masks
  module Server
    require "test_helper"

    class AccountProfileTest < ActionDispatch::IntegrationTest
      setup do
        host! host_for(@tenant)

        @actor = create_actor(@tenant, nickname: "ada", email: "ada@example.com")
      end

      def reloaded
        within(@tenant) { @actor.reload }
      end

      test "a person changes their name and nickname" do
        sign_in_as(@actor)

        patch "/account/profile", params: { name: " Ada Lovelace ", nickname: "countess" }

        assert_redirected_to "/#profile"
        assert_equal "Ada Lovelace", reloaded.name
        assert_equal "countess", reloaded.nickname
        assert within(@tenant) { Event.where(action: Event::ACTOR_UPDATED, actor: @actor, by: @actor).exists? }
      end

      test "a nickname someone else holds is refused" do
        create_actor(@tenant, nickname: "grace")
        sign_in_as(@actor)

        patch "/account/profile", params: { nickname: "Grace" }

        assert flash[:alert].present?
        assert_equal "ada", reloaded.nickname
      end

      test "only the name and nickname can be changed this way" do
        sign_in_as(@actor)

        patch "/account/profile", params: { name: "Ada", email: "elsewhere@example.com", scopes: "masks:manage" }

        assert_equal "ada@example.com", reloaded.email
        refute reloaded.manages?
      end

      test "a directory's account keeps the name the directory gave it" do
        within(@tenant) { @actor.update!(external_id: "dir-1", name: "Ada") }
        sign_in_as(@actor)

        patch "/account/profile", params: { name: "Someone" }

        assert_equal flash[:alert], I18n.t("profiles.directed")
        assert_equal "Ada", reloaded.name
      end

      test "an account without a password sets one after a recent sign-in" do
        sign_in_as(@actor)
        within(@tenant) { @actor.update_column(:password_digest, nil) }

        patch "/account/password", params: { password: "a much longer passphrase" }

        assert_redirected_to "/"
        assert reloaded.authenticate("a much longer passphrase")
      end

      test "setting a password asks for a recent sign-in" do
        sign_in_as(@actor)
        within(@tenant) { @actor.update_column(:password_digest, nil) }

        travel 16.minutes do
          patch "/account/password", params: { password: "a much longer passphrase" }

          assert_redirected_to %r{/login}
          refute reloaded.password?
        end
      end
    end
  end
end
