module Masks
  module Server
    require "test_helper"

    class AppPresetTest < ActiveSupport::TestCase
      test "every preset names its redirects, scopes, settings, and a guide" do
        AppPreset.all.each do |preset|
          assert preset.redirect_uris(base: "https://app.example.com").any?, preset.key
          assert_includes preset.scopes, "openid", preset.key
          assert preset.guide.start_with?("https://"), preset.key
        end
      end

      test "every preset makes a client masks accepts" do
        AppPreset.all.each do |preset|
          client = within do
            Client.new(client_id: SecureRandom.uuid, name: preset.name, grant_types: %w[authorization_code refresh_token],
                       response_types: Client.response_types_for(%w[authorization_code]),
                       redirect_uris: preset.redirect_uris(base: "https://app.example.com"),
                       allowed_scopes: Scopes.join(preset.scopes), approved_at: Time.current)
          end

          assert within { client.valid? }, "#{preset.key}: #{client.errors.full_messages.to_sentence}"
        end
      end

      test "every preset's redirect is a URL with a scheme and a host, and the picker lists each one" do
        keys = AppPreset.all.map(&:key)

        %w[tailscale headscale home-assistant synapse bookstack wikijs minio argocd synology].each do |key|
          assert_includes keys, key
        end

        AppPreset.all.each do |preset|
          preset.redirect_uris(base: "https://app.example.com").each do |uri|
            parsed = URI.parse(uri)

            assert parsed.host.present? || parsed.scheme == "app.immich", "#{preset.key}: #{uri}"
          end
        end
      end

      test "a tailnet's redirect is Tailscale's own, whatever address the operator enters" do
        assert_equal [ "https://login.tailscale.com/a/oauth_response" ],
                     AppPreset.find("tailscale").redirect_uris(base: "https://login.tailscale.com")
      end

      test "a redirect is built on the app's address without a doubled slash" do
        assert_equal [ "https://grafana.example.com/login/generic_oauth" ],
                     AppPreset.find("grafana").redirect_uris(base: "https://grafana.example.com/")
      end

      test "an app that names its sign-in source in the path takes the name, or its usual one" do
        gitea = AppPreset.find("gitea")

        assert_equal [ "https://git.example.com/user/oauth2/masks/callback" ], gitea.redirect_uris(base: "https://git.example.com")
        assert_equal [ "https://git.example.com/user/oauth2/home/callback" ],
                     gitea.redirect_uris(base: "https://git.example.com", name: "home")
      end

      test "an address without a scheme, or a name with a slash, is refused" do
        assert_raises(AppPreset::Unusable) { AppPreset.find("grafana").redirect_uris(base: "grafana.example.com") }
        assert_raises(AppPreset::Unusable) { AppPreset.find("gitea").redirect_uris(base: "https://git.example.com", name: "a/b") }
      end

      test "settings fill in the issuer, the endpoints, and the client's credentials" do
        issuer = Issuer.new(@tenant, "https://#{@tenant.subdomain}.auth.test")
        client = Client.new(client_id: "abc")

        settings = AppPreset.find("grafana").settings(base: "https://grafana.example.com", issuer: issuer,
                                                      client: client, secret: "s3cret")
        held = settings.to_h { |setting| [ setting["label"], setting["value"] ] }

        assert_equal "abc", held["client_id"]
        assert_equal "s3cret", held["client_secret"]
        assert_equal "#{issuer.url}/authorize", held["auth_url"]
        assert settings.none? { |setting| setting["value"].match?(/\{[a-z_]+\}/) }
      end
    end
  end
end
