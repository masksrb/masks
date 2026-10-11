module Masks
  module Server
    require "test_helper"

    class PasskeyNamesTest < ActionDispatch::IntegrationTest
      setup do
        host! host_for(@tenant)
        @actor = create_actor(nickname: "ada")
        @passkey = within { Passkey.create!(actor: @actor, external_id: "laptop", public_key: "key", sign_count: 0, user_verified: false) }
      end

      test "a person names their passkey from the account page" do
        sign_in_as(@actor)

        patch "/account/passkeys/#{@passkey.id}", params: { name: "  Work laptop " }

        assert_redirected_to "/#passkeys"
        assert_equal "Work laptop", within { @passkey.reload.name }
      end

      test "renaming does not ask for a recent sign-in" do
        sign_in_as(@actor)

        travel 1.hour do
          patch "/account/passkeys/#{@passkey.id}", params: { name: "Phone" }

          assert_redirected_to "/#passkeys"
        end
      end

      test "nobody renames someone else's passkey" do
        sign_in_as(create_actor(nickname: "grace"))

        patch "/account/passkeys/#{@passkey.id}", params: { name: "Mine now" }

        assert_nil within { @passkey.reload.name }
      end

      test "a name too long is refused" do
        sign_in_as(@actor)

        patch "/account/passkeys/#{@passkey.id}", params: { name: "x" * 65 }

        assert_equal I18n.t("passkeys.unnamed"), flash[:alert]
      end
    end
  end
end
