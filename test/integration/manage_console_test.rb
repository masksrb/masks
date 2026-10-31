module Masks
  module Server
    require "test_helper"

    class ManageConsoleTest < ActionDispatch::IntegrationTest
      setup do
        host! host_for(@tenant)
        @owner = create_actor(@tenant, nickname: "owner", scopes: Scopes::MANAGE)
      end

      def boot
        get "/manage"

        assert_response :success

        JSON.parse(Nokogiri::HTML(response.body).at_css("#manage")["data-boot"])
      end

      test "the console is a built-in client, so a fresh browser is never asked to approve it" do
        held = boot

        assert_equal Client::CONSOLE_ID, held["clientId"]

        console = within { Client.find_by!(client_id: Client::CONSOLE_ID) }

        assert console.approved?
        assert console.public?
        assert_not console.consent_required
        assert_equal [ "#{held["issuer"]}/manage/callback" ], console.redirect_uris
        assert_equal [ held["resource"] ], console.resources
        assert_includes console.allowed_scopes.split, Scopes::MANAGE
      end

      test "opening the console again reuses the same client" do
        boot
        boot

        assert_equal 1, within { Client.where(client_id: Client::CONSOLE_ID).count }
      end

      test "a console connected through a handshake before this release is kept and handed to the page" do
        earlier = create_client(@tenant, name: "Manage masks", resources: [ issuer_for(@tenant).manage_resource ],
                                         approved_at: Time.current, approved_by: @owner, redirect_uris: [ "#{issuer_for(@tenant).manage_resource}/callback" ])

        assert_equal earlier.client_id, boot["clientId"]
        assert_not within { Client.exists?(client_id: Client::CONSOLE_ID) }
      end

      test "a token from the built-in client opens the manage API" do
        console = within { Client.console!(issuer_for(@tenant)) }
        bearer = manage_bearer(@owner, console)

        body = manage("{ tenant { subdomain } }", bearer: bearer)

        assert_nil body["errors"]
        assert_equal @tenant.subdomain, body.dig("data", "tenant", "subdomain")
      end

      private

        def manage_bearer(actor, console)
          sign_in_as(actor)
          authorize(client_id: console.client_id, scope: "openid masks:manage", resource: issuer_for(@tenant).manage_resource,
                    redirect_uri: console.redirect_uris.first)

          token(grant_type: "authorization_code", code: code_from, redirect_uri: console.redirect_uris.first,
                code_verifier: verifier, client_id: console.client_id)["access_token"]
        end

        def manage(query, bearer:)
          post "/manage/graphql", params: { query: query }.to_json,
                                  headers: { "CONTENT_TYPE" => "application/json", "HTTP_AUTHORIZATION" => "Bearer #{bearer}" }

          JSON.parse(response.body)
        end
    end
  end
end
