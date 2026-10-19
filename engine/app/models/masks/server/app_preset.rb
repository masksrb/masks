module Masks
  module Server
    class AppPreset
      class Unusable < StandardError; end

      NAME = /\A[A-Za-z0-9_-]{1,64}\z/

      ALL = [
        {
          key: "proxy", name: "Any app behind Caddy, Traefik, or nginx", forward: true,
          redirects: [ "{base}/masks-auth/callback" ],
          scopes: %w[openid],
          guide: "https://masks.pages.dev/guides/forward-auth/",
          settings: [
            [ "Caddy", "{host} {\n  forward_auth {masks_origin} {\n    uri /forward-auth\n    header_up Host {masks_host}\n" \
                       "    copy_headers Remote-User Remote-Email Remote-Name Remote-Groups\n  }\n  reverse_proxy your-app:8080\n}" ],
            [ "Traefik", "http:\n  middlewares:\n    masks:\n      forwardAuth:\n        address: {forward_auth}\n" \
                         "        authResponseHeaders: [Remote-User, Remote-Email, Remote-Name, Remote-Groups]" ],
            [ "nginx", "location = /masks-check {\n  internal;\n  proxy_pass {forward_auth}?status=401;\n" \
                       "  proxy_pass_request_body off;\n  proxy_set_header Content-Length \"\";\n" \
                       "  proxy_set_header X-Original-URL $scheme://$http_host$request_uri;\n  proxy_ssl_server_name on;\n}\n" \
                       "location /masks-auth/ {\n  proxy_pass {masks_origin}/forward-auth/;\n" \
                       "  proxy_set_header X-Forwarded-Host $host;\n  proxy_set_header X-Forwarded-Proto $scheme;\n" \
                       "  proxy_ssl_server_name on;\n}\n" \
                       "location / {\n  auth_request /masks-check;\n  auth_request_set $remote_user $upstream_http_remote_user;\n" \
                       "  proxy_set_header Remote-User $remote_user;\n" \
                       "  error_page 401 =302 {masks_origin}/forward-auth/start?rd=$scheme://$http_host$request_uri;\n" \
                       "  proxy_pass http://your-app:8080;\n}" ]
          ]
        },
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
        },
        {
          key: "tailscale", name: "Tailscale",
          redirects: [ "https://login.tailscale.com/a/oauth_response" ],
          scopes: %w[openid profile email],
          guide: "https://tailscale.com/kb/1240/sso-custom-oidc",
          settings: [
            [ "WebFinger domain", "{masks_host}" ], [ "Issuer URL", "{issuer}" ],
            [ "Client ID", "{client_id}" ], [ "Client secret", "{client_secret}" ]
          ]
        },
        {
          key: "headscale", name: "Headscale",
          redirects: [ "{base}/oidc/callback" ],
          scopes: %w[openid profile email groups],
          guide: "https://headscale.net/stable/ref/oidc/",
          settings: [
            [ "oidc.issuer", "{issuer}" ], [ "oidc.client_id", "{client_id}" ], [ "oidc.client_secret", "{client_secret}" ],
            [ "oidc.scope", "[openid, profile, email, groups]" ], [ "oidc.allowed_groups", "[admins]" ]
          ]
        },
        {
          key: "home-assistant", name: "Home Assistant (OIDC integration)",
          redirects: [ "{base}/auth/oidc/callback" ],
          scopes: %w[openid profile email groups],
          guide: "https://github.com/christiaangoossens/hass-oidc-auth",
          settings: [
            [ "auth_oidc.discovery_url", "{discovery}" ], [ "auth_oidc.client_id", "{client_id}" ],
            [ "auth_oidc.client_secret", "{client_secret}" ], [ "auth_oidc.display_name", "{tenant}" ],
            [ "auth_oidc.roles.admin", "admins" ]
          ]
        },
        {
          key: "synapse", name: "Matrix (Synapse)", asks: { "name" => "masks" },
          redirects: [ "{base}/_synapse/client/oidc/callback" ],
          scopes: %w[openid profile email],
          guide: "https://element-hq.github.io/synapse/latest/openid.html",
          settings: [
            [ "oidc_providers", "- idp_id: {name}\n  idp_name: {tenant}\n  issuer: {issuer}\n  client_id: {client_id}\n" \
                                "  client_secret: {client_secret}\n  scopes: [openid, profile, email]\n" \
                                "  user_mapping_provider:\n    config:\n      localpart_template: \"{{ user.preferred_username }}\"\n" \
                                "      display_name_template: \"{{ user.name }}\"\n      email_template: \"{{ user.email }}\"" ]
          ]
        },
        {
          key: "bookstack", name: "BookStack",
          redirects: [ "{base}/oidc/callback" ],
          scopes: %w[openid profile email groups],
          guide: "https://www.bookstackapp.com/docs/admin/oidc-auth/",
          settings: [
            [ "AUTH_METHOD", "oidc" ], [ "OIDC_NAME", "{tenant}" ], [ "OIDC_ISSUER", "{issuer}" ], [ "OIDC_ISSUER_DISCOVER", "true" ],
            [ "OIDC_CLIENT_ID", "{client_id}" ], [ "OIDC_CLIENT_SECRET", "{client_secret}" ],
            [ "OIDC_DISPLAY_NAME_CLAIMS", "name" ], [ "OIDC_ADDITIONAL_SCOPES", "groups" ],
            [ "OIDC_USER_TO_GROUPS", "true" ], [ "OIDC_GROUPS_CLAIM", "groups" ], [ "OIDC_REMOVE_FROM_GROUPS", "true" ]
          ]
        },
        {
          key: "wikijs", name: "Wiki.js", asks: { "name" => "masks" },
          redirects: [ "{base}/login/{name}/callback" ],
          scopes: %w[openid profile email groups],
          guide: "https://docs.requarks.io/auth/oidc",
          settings: [
            [ "Client ID", "{client_id}" ], [ "Client Secret", "{client_secret}" ],
            [ "Authorization Endpoint URL", "{authorize}" ], [ "Token Endpoint URL", "{token}" ],
            [ "User Info Endpoint URL", "{userinfo}" ], [ "Issuer", "{issuer}" ], [ "Logout URL", "{logout}" ],
            [ "Email Claim", "email" ], [ "Display Name Claim", "name" ], [ "Groups Claim", "groups" ],
            [ "Callback URL", "{base}/login/{name}/callback" ]
          ]
        },
        {
          key: "minio", name: "MinIO",
          redirects: [ "{base}/oauth_callback" ],
          scopes: %w[openid profile email groups],
          guide: "https://min.io/docs/minio/linux/operations/external-iam/configure-openid-external-identity-management.html",
          settings: [
            [ "MINIO_IDENTITY_OPENID_CONFIG_URL", "{discovery}" ], [ "MINIO_IDENTITY_OPENID_CLIENT_ID", "{client_id}" ],
            [ "MINIO_IDENTITY_OPENID_CLIENT_SECRET", "{client_secret}" ], [ "MINIO_IDENTITY_OPENID_SCOPES", "openid,profile,email,groups" ],
            [ "MINIO_IDENTITY_OPENID_CLAIM_NAME", "groups" ], [ "MINIO_IDENTITY_OPENID_REDIRECT_URI", "{base}/oauth_callback" ],
            [ "MINIO_IDENTITY_OPENID_DISPLAY_NAME", "{tenant}" ]
          ]
        },
        {
          key: "argocd", name: "Argo CD",
          redirects: [ "{base}/auth/callback", "{base}/api/dex/callback" ],
          scopes: %w[openid profile email groups],
          guide: "https://argo-cd.readthedocs.io/en/stable/operator-manual/user-management/#existing-oidc-provider",
          settings: [
            [ "argocd-cm oidc.config", "name: {tenant}\nissuer: {issuer}\nclientID: {client_id}\nclientSecret: {client_secret}\n" \
                                       "requestedScopes: [openid, profile, email, groups]" ],
            [ "argocd-rbac-cm policy.csv", "g, admins, role:admin" ], [ "argocd-rbac-cm scopes", "[groups]" ]
          ]
        },
        {
          key: "synology", name: "Synology DSM",
          redirects: [ "{base}", "{base}/" ],
          scopes: %w[openid profile email],
          guide: "https://kb.synology.com/en-global/DSM/help/DSM/AdminCenter/connection_sso_client",
          settings: [
            [ "Profile", "OIDC" ], [ "Name", "{tenant}" ], [ "Well Known URL", "{discovery}" ],
            [ "Client ID", "{client_id}" ], [ "Client secret", "{client_secret}" ],
            [ "Scope", "openid profile email" ], [ "Username claim", "preferred_username" ], [ "Redirect URI", "{base}" ]
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
      def forward? = definition.fetch(:forward, false)

      def redirect_uris(base:, name: nil)
        definition[:redirects].map { |template| fill(template, values(base: base, name: name)) }.uniq
      end

      def settings(base:, issuer:, client:, secret:, name: nil)
        known = values(base: base, name: name).merge(
          "issuer" => issuer.url, "discovery" => "#{issuer.url}/.well-known/openid-configuration",
          "authorize" => issuer.discovery["authorization_endpoint"], "token" => issuer.discovery["token_endpoint"],
          "userinfo" => issuer.discovery["userinfo_endpoint"], "logout" => issuer.discovery["end_session_endpoint"],
          "client_id" => client.client_id, "client_secret" => secret.to_s, "tenant" => issuer.tenant.name,
          "forward_auth" => "#{issuer.url}/forward-auth", "masks_origin" => Forwarded.origin(issuer.url).to_s,
          "masks_host" => URI.parse(issuer.url).host, "host" => URI.parse(known_base(base)).host
        )

        definition[:settings].map { |label, template| { "label" => label, "value" => fill(template, known) } }
      end

      private

        def known_base(base)
          base.to_s.strip.delete_suffix("/")
        end

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
