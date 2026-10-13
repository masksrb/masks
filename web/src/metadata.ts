export const CLIENT_PATH = "/oauth/client.json";

export interface ClientMetadataOptions {
  origin: string;
  name: string;
  path?: string;
  redirectUris?: string[];
  postLogoutRedirectUris?: string[];
  scope?: string | string[];
  logoUri?: string;
  dpop?: boolean;
}

export function clientMetadata(
  options: ClientMetadataOptions,
): Record<string, unknown> {
  const origin = new URL(options.origin).origin;
  const home = `${origin}/`;
  const scope = Array.isArray(options.scope)
    ? options.scope.join(" ")
    : options.scope;

  return {
    client_id: `${origin}${options.path ?? CLIENT_PATH}`,
    client_name: options.name,
    client_uri: home,
    redirect_uris: options.redirectUris ?? [home],
    post_logout_redirect_uris: options.postLogoutRedirectUris ?? [home],
    grant_types: ["authorization_code", "refresh_token"],
    response_types: ["code"],
    token_endpoint_auth_method: "none",
    application_type: "web",
    ...(scope ? { scope } : {}),
    ...(options.logoUri ? { logo_uri: options.logoUri } : {}),
    ...(options.dpop ? { dpop_bound_access_tokens: true } : {}),
  };
}
