module Masks
  module Server
    require "test_helper"

    class AccountLauncherTest < ActionDispatch::IntegrationTest
      setup do
        host! host_for(@tenant)
        @actor = create_actor(nickname: "ada")
      end

      def tiles
        get "/"

        response.body.scan(/<a class="app-tile" href="([^"]+)"/).flatten
      end

      test "an approved app with a home page appears on the account page" do
        create_client(name: "Wiki", client_uri: "https://wiki.example.com", approved_at: Time.current)
        sign_in_as(@actor)

        assert_equal [ "https://wiki.example.com" ], tiles
      end

      test "an app nobody approved never appears, whatever home page it names" do
        create_client(name: "Lookalike", client_uri: "https://phish.example.com")
        sign_in_as(@actor)

        assert_empty tiles
        assert_no_match "Your apps", response.body
      end

      test "an app limited to groups the person is outside of does not appear" do
        create_client(name: "Admin", client_uri: "https://admin.example.com", approved_at: Time.current,
                      allowed_groups: %w[admins])
        sign_in_as(@actor)

        assert_empty tiles
      end

      test "a SAML app that starts its own sign-in opens through masks" do
        client = create_client(name: "Files", protocol: SamlIdentity::PROTOCOL, approved_at: Time.current,
                               saml_entity_id: "https://files.example.com/saml", saml_idp_initiated: true,
                               redirect_uris: [ "https://files.example.com/saml/acs" ], grant_types: [],
                               response_types: [])
        sign_in_as(@actor)

        assert_equal [ "/saml/initiate/#{client.client_id}" ], tiles
      end
    end
  end
end
