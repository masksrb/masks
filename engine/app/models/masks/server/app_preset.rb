module Masks
  module Server
    class AppPreset
      class Unusable < StandardError; end

      NAME = /\A[A-Za-z0-9_-]{1,64}\z/

      ALL = [
        {
          key: "grafana", name: "Grafana",
          redirects: [ "{base}/login/generic_oauth" ],
          scopes: %w[openid profile email groups offline_access],
          guide: "https://grafana.com/docs/grafana/latest/setup-grafana/configure-access/configure-authentication/generic-oauth/",
          settings: [
            [ "[auth.generic_oauth] enabled", "true" ],
            [ "client_id", "{client_id}" ], [ "client_secret", "{client_secret}" ],
            [ "scopes", "openid profile email groups offline_access" ],
            [ "auth_url", "{authorize}" ], [ "token_url", "{token}" ], [ "api_url", "{userinfo}" ],
            [ "role_attribute_path", "contains(groups[*], 'admins') && 'Admin' || 'Viewer'" ]
          ]
        },
        {
          key: "nextcloud", name: "Nextcloud",
          redirects: [ "{base}/apps/user_oidc/code", "{base}/index.php/apps/user_oidc/code" ],
          scopes: %w[openid profile email groups],
          guide: "https://github.com/nextcloud/user_oidc",
          settings: [
            [ "occ user_oidc:provider", "masks --clientid={client_id} --clientsecret={client_secret} " \
                                        "--discoveryuri={discovery} --group-provisioning=1" ]
          ]
        },
        {
          key: "gitea", name: "Gitea", asks: { "name" => "masks" },
          redirects: [ "{base}/user/oauth2/{name}/callback" ],
          scopes: %w[openid profile email groups],
          guide: "https://docs.gitea.com/administration/authentication/",
          settings: [
            [ "gitea admin auth add-oauth", "--name {name} --provider openidConnect --key {client_id} " \
                                            "--secret {client_secret} --auto-discover-url {discovery} " \
                                            "--scopes \"email profile groups\" --group-claim-name groups --admin-group admins" ]
          ]
        },
        {
          key: "forgejo", name: "Forgejo", asks: { "name" => "masks" },
          redirects: [ "{base}/user/oauth2/{name}/callback" ],
          scopes: %w[openid profile email groups],
          guide: "https://forgejo.org/docs/latest/admin/advanced/oidc-group-mappings/",
          settings: [
            [ "forgejo admin auth add-oauth", "--name {name} --provider openidConnect --key {client_id} " \
                                              "--secret {client_secret} --auto-discover-url {discovery} " \
                                              "--scopes \"email profile groups\" --group-claim-name groups" ]
          ]
        },
        {
          key: "immich", name: "Immich",
          redirects: [ "app.immich:///oauth-callback", "{base}/auth/login", "{base}/user-settings" ],
          scopes: %w[openid profile email],
          guide: "https://docs.immich.app/administration/oauth/",
          settings: [
            [ "Issuer URL", "{issuer}" ], [ "Client ID", "{client_id}" ], [ "Client Secret", "{client_secret}" ],
            [ "Scope", "openid email profile" ], [ "Token Endpoint Auth Method", "client_secret_post" ]
          ]
        },
        {
          key: "outline", name: "Outline",
          redirects: [ "{base}/auth/oidc.callback" ],
          scopes: %w[openid profile email offline_access],
          guide: "https://docs.getoutline.com/s/hosting/doc/oidc-8CPBm6uC0I",
          settings: [
            [ "OIDC_ISSUER_URL", "{issuer}" ], [ "OIDC_CLIENT_ID", "{client_id}" ],
            [ "OIDC_CLIENT_SECRET", "{client_secret}" ], [ "OIDC_SCOPES", "openid profile email offline_access" ],
            [ "OIDC_DISPLAY_NAME", "{tenant}" ]
          ]
        },
        {
          key: "audiobookshelf", name: "Audiobookshelf",
          redirects: [ "{base}/auth/openid/callback", "{base}/auth/openid/mobile-redirect" ],
          scopes: %w[openid profile email],
          guide: "https://www.audiobookshelf.org/guides/oidc_authentication/",
          settings: [
            [ "Issuer URL", "{issuer}" ], [ "Client ID", "{client_id}" ], [ "Client Secret", "{client_secret}" ]
          ]
        },
        {
          key: "paperless", name: "Paperless-ngx", asks: { "name" => "masks" },
          redirects: [ "{base}/accounts/oidc/{name}/login/callback/" ],
          scopes: %w[openid profile email groups],
          guide: "https://docs.paperless-ngx.com/advanced_usage/",
          settings: [
            [ "PAPERLESS_APPS", "allauth.socialaccount.providers.openid_connect" ],
            [ "PAPERLESS_SOCIALACCOUNT_PROVIDERS",
              "{\"openid_connect\":{\"SCOPE\":[\"openid\",\"profile\",\"email\",\"groups\"],\"APPS\":[{\"provider_id\":\"{name}\"," \
              "\"name\":\"{tenant}\",\"client_id\":\"{client_id}\",\"secret\":\"{client_secret}\"," \
              "\"settings\":{\"server_url\":\"{discovery}\"}}]}}" ],
            [ "PAPERLESS_SOCIAL_ACCOUNT_SYNC_GROUPS", "true" ]
          ]
        },
        {
          key: "portainer", name: "Portainer",
          redirects: [ "{base}", "{base}/" ],
          scopes: %w[openid profile email],
          guide: "https://docs.portainer.io/admin/settings/authentication/oauth",
          settings: [
            [ "Client ID", "{client_id}" ], [ "Client secret", "{client_secret}" ],
            [ "Authorization URL", "{authorize}" ], [ "Access token URL", "{token}" ], [ "Resource URL", "{userinfo}" ],
            [ "Redirect URL", "{base}" ], [ "Logout URL", "{logout}" ], [ "User identifier", "preferred_username" ],
            [ "Scopes", "openid profile email" ]
          ]
        },
        {
          key: "proxmox", name: "Proxmox VE", asks: { "name" => "masks" },
          redirects: [ "{base}" ],
          scopes: %w[openid profile email groups],
          guide: "https://pve.proxmox.com/wiki/User_Management",
          settings: [
            [ "pveum realm add", "{name} --type openid --issuer-url {issuer} --client-id {client_id} " \
                                 "--client-key {client_secret} --username-claim username --autocreate 1 " \
                                 "--scopes \"email profile groups\" --groups-claim groups" ]
          ]
        },
        {
          key: "jellyfin", name: "Jellyfin (SSO plugin)", asks: { "name" => "masks" },
          redirects: [ "{base}/sso/OID/redirect/{name}", "{base}/sso/OID/r/{name}" ],
          scopes: %w[openid profile groups],
          guide: "https://github.com/9p4/jellyfin-plugin-sso",
          settings: [
            [ "OID Endpoint", "{issuer}" ], [ "OID Client ID", "{client_id}" ], [ "OID Secret", "{client_secret}" ],
            [ "Request Additional Scopes", "groups" ], [ "Role Claim", "groups" ], [ "Admin Roles", "admins" ]
          ]
        },
        {
          key: "vaultwarden", name: "Vaultwarden",
          redirects: [ "{base}/identity/connect/oidc-signin" ],
          scopes: %w[openid profile email],
          guide: "https://github.com/dani-garcia/vaultwarden/wiki/Enabling-SSO-support-using-OpenId-Connect",
          settings: [
            [ "SSO_ENABLED", "true" ], [ "SSO_AUTHORITY", "{issuer}" ],
            [ "SSO_CLIENT_ID", "{client_id}" ], [ "SSO_CLIENT_SECRET", "{client_secret}" ]
          ]
        },
        {
          key: "mealie", name: "Mealie",
          redirects: [ "{base}/login", "{base}/login?direct=1" ],
          scopes: %w[openid profile email groups],
          guide: "https://mealie.io/documentation/getting-started/authentication/oidc-v2/",
          settings: [
            [ "OIDC_AUTH_ENABLED", "true" ], [ "OIDC_CONFIGURATION_URL", "{discovery}" ],
            [ "OIDC_CLIENT_ID", "{client_id}" ], [ "OIDC_CLIENT_SECRET", "{client_secret}" ],
            [ "OIDC_ADMIN_GROUP", "admins" ], [ "OIDC_PROVIDER_NAME", "{tenant}" ]
          ]
        },
        {
          key: "open-webui", name: "Open WebUI",
          redirects: [ "{base}/oauth/oidc/callback" ],
          scopes: %w[openid profile email groups],
          guide: "https://docs.openwebui.com/features/authentication-access/auth/sso/",
          settings: [
            [ "OPENID_PROVIDER_URL", "{discovery}" ], [ "OAUTH_CLIENT_ID", "{client_id}" ],
            [ "OAUTH_CLIENT_SECRET", "{client_secret}" ], [ "OAUTH_SCOPES", "openid email profile groups" ],
            [ "OAUTH_PROVIDER_NAME", "{tenant}" ], [ "ENABLE_OAUTH_SIGNUP", "true" ],
            [ "ENABLE_OAUTH_ROLE_MANAGEMENT", "true" ], [ "OAUTH_ROLES_CLAIM", "groups" ], [ "OAUTH_ADMIN_ROLES", "admins" ]
          ]
        }
      ].map(&:freeze).freeze

      class << self
        def all
          ALL.map { |definition| new(definition) }
        end

        def find(key)
          definition = ALL.find { |held| held[:key] == key.to_s }

          definition && new(definition)
        end
      end

      attr_reader :definition

      def initialize(definition)
        @definition = definition
      end

      def key = definition[:key]
      def name = definition[:name]
      def asks = definition.fetch(:asks, {})
      def scopes = definition[:scopes]
      def guide = definition[:guide]

      def redirect_uris(base:, name: nil)
        definition[:redirects].map { |template| fill(template, values(base: base, name: name)) }.uniq
      end

      def settings(base:, issuer:, client:, secret:, name: nil)
        known = values(base: base, name: name).merge(
          "issuer" => issuer.url, "discovery" => "#{issuer.url}/.well-known/openid-configuration",
          "authorize" => issuer.discovery["authorization_endpoint"], "token" => issuer.discovery["token_endpoint"],
          "userinfo" => issuer.discovery["userinfo_endpoint"], "logout" => issuer.discovery["end_session_endpoint"],
          "client_id" => client.client_id, "client_secret" => secret.to_s, "tenant" => issuer.tenant.name
        )

        definition[:settings].map { |label, template| { "label" => label, "value" => fill(template, known) } }
      end

      private

        def values(base:, name:)
          trimmed = base.to_s.strip.delete_suffix("/")
          named = name.presence || asks["name"]

          raise Unusable, "the address must start with http:// or https://" unless trimmed.match?(%r{\Ahttps?://[^/\s]+})
          raise Unusable, "the name may hold letters, digits, dashes, and underscores" if asks.key?("name") && !named.to_s.match?(NAME)

          { "base" => trimmed, "name" => named }
        end

        def fill(template, known)
          template.gsub(/\{([a-z_]+)\}/) { known.fetch(Regexp.last_match(1)) { Regexp.last_match(0) } }
        end
    end
  end
end
