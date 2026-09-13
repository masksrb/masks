class ProviderPreset
  class Unusable < StandardError; end

  VARIABLES = {
    "domain" => /\A[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+(:\d{1,5})?\z/i,
    "tenant" => /\A[a-z0-9][a-z0-9.-]{0,127}\z/i,
    "realm" => /\A[A-Za-z0-9_-]{1,64}\z/
  }.freeze

  SETTINGS = %i[
    protocol issuer authorization_url token_url userinfo_url emails_url jwks_uri
    scopes subject_claim claims trusts_email token_auth_method response_mode authorize_params name_id_format
  ].freeze

  ALL = [
    {
      key: "google", name: "Google", protocol: "oidc",
      issuer: "https://accounts.google.com",
      authorization_url: "https://accounts.google.com/o/oauth2/v2/auth",
      token_url: "https://oauth2.googleapis.com/token",
      userinfo_url: "https://openidconnect.googleapis.com/v1/userinfo",
      jwks_uri: "https://www.googleapis.com/oauth2/v3/certs",
      trusts_email: true,
      guide: "https://console.cloud.google.com/apis/credentials"
    },
    {
      key: "microsoft", name: "Microsoft", protocol: "oidc",
      issuer: "https://login.microsoftonline.com/{tenant}/v2.0",
      asks: %w[tenant],
      guide: "https://entra.microsoft.com/#view/Microsoft_AAD_RegisteredApps/ApplicationsListBlade"
    },
    {
      key: "apple", name: "Apple", protocol: "oidc",
      issuer: "https://appleid.apple.com",
      authorization_url: "https://appleid.apple.com/auth/authorize",
      token_url: "https://appleid.apple.com/auth/token",
      jwks_uri: "https://appleid.apple.com/auth/keys",
      scopes: "name email",
      response_mode: "form_post",
      token_auth_method: "signed_secret",
      trusts_email: true,
      needs: %w[team_id key_id private_key],
      guide: "https://developer.apple.com/account/resources/identifiers/list/serviceId"
    },
    {
      key: "github", name: "GitHub", protocol: "oauth2",
      authorization_url: "https://github.com/login/oauth/authorize",
      token_url: "https://github.com/login/oauth/access_token",
      userinfo_url: "https://api.github.com/user",
      emails_url: "https://api.github.com/user/emails",
      scopes: "read:user user:email",
      subject_claim: "id",
      claims: { "preferred_username" => "login", "name" => "name", "picture" => "avatar_url", "profile" => "html_url" },
      trusts_email: true,
      guide: "https://github.com/settings/developers"
    },
    {
      key: "gitlab", name: "GitLab", protocol: "oidc",
      issuer: "https://{domain}",
      asks: %w[domain],
      defaults: { "domain" => "gitlab.com" },
      trusts_email: true,
      guide: "https://gitlab.com/-/user_settings/applications"
    },
    {
      key: "slack", name: "Slack", protocol: "oidc",
      issuer: "https://slack.com",
      authorization_url: "https://slack.com/openid/connect/authorize",
      token_url: "https://slack.com/api/openid.connect.token",
      userinfo_url: "https://slack.com/api/openid.connect.userInfo",
      jwks_uri: "https://slack.com/openid/connect/keys",
      trusts_email: true,
      guide: "https://api.slack.com/apps"
    },
    {
      key: "linkedin", name: "LinkedIn", protocol: "oidc",
      issuer: "https://www.linkedin.com/oauth",
      authorization_url: "https://www.linkedin.com/oauth/v2/authorization",
      token_url: "https://www.linkedin.com/oauth/v2/accessToken",
      userinfo_url: "https://api.linkedin.com/v2/userinfo",
      jwks_uri: "https://www.linkedin.com/oauth/openid/jwks",
      trusts_email: true,
      guide: "https://www.linkedin.com/developers/apps"
    },
    {
      key: "discord", name: "Discord", protocol: "oauth2",
      authorization_url: "https://discord.com/oauth2/authorize",
      token_url: "https://discord.com/api/oauth2/token",
      userinfo_url: "https://discord.com/api/users/@me",
      scopes: "identify email",
      subject_claim: "id",
      claims: { "email_verified" => "verified", "preferred_username" => "username", "name" => "global_name" },
      trusts_email: true,
      guide: "https://discord.com/developers/applications"
    },
    {
      key: "facebook", name: "Facebook", protocol: "oauth2",
      authorization_url: "https://www.facebook.com/v23.0/dialog/oauth",
      token_url: "https://graph.facebook.com/v23.0/oauth/access_token",
      userinfo_url: "https://graph.facebook.com/v23.0/me?fields=id,name,email,first_name,last_name,picture",
      scopes: "public_profile email",
      subject_claim: "id",
      claims: { "given_name" => "first_name", "family_name" => "last_name", "picture" => "picture.data.url" },
      guide: "https://developers.facebook.com/apps"
    },
    {
      key: "x", name: "X", protocol: "oauth2",
      authorization_url: "https://x.com/i/oauth2/authorize",
      token_url: "https://api.x.com/2/oauth2/token",
      userinfo_url: "https://api.x.com/2/users/me?user.fields=profile_image_url",
      scopes: "users.read tweet.read",
      subject_claim: "data.id",
      claims: { "preferred_username" => "data.username", "name" => "data.name", "picture" => "data.profile_image_url" },
      token_auth_method: "client_secret_basic",
      guide: "https://developer.x.com/en/portal/projects-and-apps"
    },
    {
      key: "okta", name: "Okta", protocol: "oidc",
      issuer: "https://{domain}",
      asks: %w[domain],
      guide: "https://help.okta.com/en-us/content/topics/apps/apps_app_integration_wizard_oidc.htm"
    },
    {
      key: "auth0", name: "Auth0", protocol: "oidc",
      issuer: "https://{domain}",
      asks: %w[domain],
      guide: "https://manage.auth0.com/#/applications"
    },
    {
      key: "keycloak", name: "Keycloak", protocol: "oidc",
      issuer: "https://{domain}/realms/{realm}",
      asks: %w[domain realm],
      guide: "https://www.keycloak.org/docs/latest/server_admin/#_oidc_clients"
    },
    {
      key: "entra-saml", name: "Microsoft Entra (SAML)", protocol: "saml",
      claims: {
        "email" => "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/emailaddress",
        "given_name" => "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/givenname",
        "family_name" => "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/surname",
        "name" => "http://schemas.microsoft.com/identity/claims/displayname"
      },
      needs: %w[metadata],
      guide: "https://learn.microsoft.com/entra/identity/enterprise-apps/add-application-portal-setup-sso"
    },
    {
      key: "okta-saml", name: "Okta (SAML)", protocol: "saml",
      claims: { "given_name" => "firstName", "family_name" => "lastName" },
      needs: %w[metadata],
      guide: "https://help.okta.com/en-us/content/topics/apps/apps_app_integration_wizard_saml.htm"
    },
    {
      key: "google-workspace-saml", name: "Google Workspace (SAML)", protocol: "saml",
      name_id_format: "urn:oasis:names:tc:SAML:1.1:nameid-format:emailAddress",
      needs: %w[metadata],
      guide: "https://support.google.com/a/answer/12032922"
    },
    { key: "oidc", name: "OpenID Connect", protocol: "oidc", custom: true },
    { key: "oauth2", name: "OAuth 2.0", protocol: "oauth2", custom: true },
    { key: "saml", name: "SAML 2.0", protocol: "saml", custom: true, needs: %w[metadata] }
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
  def protocol = definition[:protocol]
  def asks = definition.fetch(:asks, [])
  def needs = definition.fetch(:needs, %w[client_secret])
  def defaults = definition.fetch(:defaults, {})
  def guide = definition[:guide]
  def custom? = definition.fetch(:custom, false)

  def attributes(values = {})
    given = defaults.merge(values.to_h.stringify_keys.slice(*asks).compact_blank)

    asks.each do |variable|
      raise Unusable, "#{name} needs a #{variable}" if given[variable].blank?
      raise Unusable, "#{given[variable]} is not a usable #{variable}" unless given[variable].to_s.match?(VARIABLES.fetch(variable))
    end

    SETTINGS.each_with_object(preset: key) do |setting, held|
      value = definition[setting]
      next if value.nil?

      held[setting] = value.is_a?(String) ? interpolate(value, given) : value
    end
  end

  private

    def interpolate(value, given)
      value.gsub(/\{(\w+)\}/) do
        variable = Regexp.last_match(1)
        held = given.fetch(variable).to_s

        variable == "domain" ? held.downcase : held
      end
    end
end
