export const CLIENT_PATH = "/oauth/client.json";

export function list(value: string | string[] | undefined): string[] {
  if (!value) return [];

  return Array.isArray(value) ? value : value.split(/\s+/).filter(Boolean);
}

export interface ClientMetadataOptions {
  origin: string;
  name: string;
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
  const scope = list(options.scope).join(" ");

  return {
    client_id: `${origin}${CLIENT_PATH}`,
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
