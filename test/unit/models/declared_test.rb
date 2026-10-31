module Masks
  module Server
    require "test_helper"

    class DeclaredTest < ActiveSupport::TestCase
      def apply(document)
        within { Declared.new(document).apply! }
      end

      def single(document)
        { "tenants" => { @tenant.subdomain => document } }
      end

      setup do
        @ada = create_actor(nickname: "ada")
      end

      test "an app from a preset is registered with a fixed client id and its secret printed once" do
        said = apply(single("apps" => { "grafana" => { "preset" => "grafana", "url" => "https://grafana.example.com" } }))

        client = within { Client.find_by!(client_id: "grafana") }
        assert_equal [ "https://grafana.example.com/login/generic_oauth" ], client.redirect_uris
        assert client.approved?
        assert_match "has the client secret", said.first

        assert_empty apply(single("apps" => { "grafana" => { "preset" => "grafana", "url" => "https://grafana.example.com" } })),
                     "applying again prints no new secret"
      end

      test "limits at the top of the file belong to the server, and are not read as a tenant's settings" do
        said = apply({ "limits" => { "token" => 5 }, "tenants" => { @tenant.subdomain => { "name" => "Declared" } } })

        assert_empty said
        assert_equal "Declared", @tenant.reload.name

        assert_empty apply({ "limits" => { "token" => 5 } }), "a file with only limits declares nothing about any tenant"
      end

      test "a secret named by an environment variable is the one the app can use" do
        named = "DECLARED_TEST_SECRET"
        ENV[named] = "a-secret-the-app-already-has"

        said = apply(single("apps" => { "wiki" => { "redirect_uris" => [ "https://wiki.example.com/cb" ],
                                                    "client_secret_env" => named } }))

        assert_empty said
        assert within { Client.find_by!(client_id: "wiki").authenticate_secret("a-secret-the-app-already-has") }
      ensure
        ENV.delete(named)
      end

      test "groups are made, people put in them, and an app limited to one" do
        apply(single(
          "groups" => { "admins" => { "name" => "Admins", "members" => [ "ada" ] } },
          "apps" => { "dash" => { "preset" => "proxy", "url" => "https://dash.example.com", "allowed_groups" => [ "admins" ] } }
        ))

        within do
          assert_equal %w[admins], @ada.reload.group_labels
          assert Client.find_by!(client_id: "dash").forward?
          assert_equal %w[admins], Client.find_by!(client_id: "dash").allowed_groups
        end
      end

      test "a changed declaration updates what it declared and leaves everything else" do
        other = create_client(name: "Kept")
        apply(single("apps" => { "grafana" => { "preset" => "grafana", "url" => "https://old.example.com" } }))
        apply(single("apps" => { "grafana" => { "preset" => "grafana", "url" => "https://new.example.com" } }))

        within do
          assert_equal [ "https://new.example.com/login/generic_oauth" ], Client.find_by!(client_id: "grafana").redirect_uris
          assert Client.exists?(other.id)
        end
      end

      test "a declared tenant sets how long its emailed links last" do
        apply(single("password_reset_lifetime" => 900, "invitation_lifetime" => 86_400))

        assert_equal 900, @tenant.reload.password_reset_lifetime
        assert_equal 86_400, @tenant.invitation_lifetime
        assert_equal 2.days.to_i, @tenant.email_verification_lifetime

        error = assert_raises(Declared::Invalid) { apply(single("password_reset_lifetime" => 60)) }
        assert_match "Password reset lifetime must be from 5 minutes to 1 day", error.message
      end

      test "a mistake names where it is" do
        error = assert_raises(Declared::Invalid) { apply(single("apps" => { "x" => { "presett" => "grafana" } })) }
        assert_match "app x names presett", error.message

        error = assert_raises(Declared::Invalid) { apply(single("groups" => { "kids" => { "members" => [ "nobody" ] } })) }
        assert_match "nobody, who has no account", error.message

        error = assert_raises(Declared::Invalid) { apply({ "tenants" => { "missing" => {} } }) }
        assert_match "no tenant called missing", error.message
      end
    end
  end
end
