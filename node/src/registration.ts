import type { JWK } from "jose";
import { type AuthMethod, Client } from "./client.js";
import { Refused } from "./errors.js";
import { sendJSON } from "./http.js";
import type { Issuer } from "./issuer.js";
import type { Key } from "./key.js";

export interface ClientMetadata {
  client_name?: string;
  redirect_uris?: string[];
  grant_types?: string[];
  response_types?: string[];
  scope?: string;
  token_endpoint_auth_method?: AuthMethod;
  application_type?: string;
  client_uri?: string;
  logo_uri?: string;
  jwks?: { keys: JWK[] };
  jwks_uri?: string;
  resources?: string[];
  dpop_bound_access_tokens?: boolean;
  backchannel_logout_uri?: string;
}

export interface Registration extends ClientMetadata {
  client_id: string;
  client_secret?: string;
  client_secret_expires_at?: number;
  client_id_issued_at?: number;
  registration_access_token?: string;
  registration_client_uri?: string;
}

export async function register(
  issuer: Issuer,
  metadata: ClientMetadata,
  initialAccessToken?: string,
): Promise<Registration> {
  let endpoint = issuer.metadata.registration_endpoint;

  if (!endpoint && initialAccessToken) endpoint = `${issuer.url}/register`;

  if (!endpoint) {
    throw new Refused(
      "access_denied",
      `${issuer.url} registers no clients without an initial access token`,
    );
  }

  const held = await sendJSON<Registration>(
    issuer.options,
    "POST",
    endpoint,
    initialAccessToken,
    metadata,
  );

  owned(issuer, held);

  return held;
}

export async function readRegistration(
  issuer: Issuer,
  held: Registration,
): Promise<Registration> {
  owned(issuer, held);

  return kept(
    held,
    await sendJSON<Registration>(
      issuer.options,
      "GET",
      held.registration_client_uri as string,
      held.registration_access_token,
    ),
  );
}

export async function updateRegistration(
  issuer: Issuer,
  held: Registration,
  metadata: ClientMetadata,
): Promise<Registration> {
  owned(issuer, held);

  return kept(
    held,
    await sendJSON<Registration>(
      issuer.options,
      "PUT",
      held.registration_client_uri as string,
      held.registration_access_token,
      metadata,
    ),
  );
}

export async function deleteRegistration(
  issuer: Issuer,
  held: Registration,
): Promise<void> {
  owned(issuer, held);

  await sendJSON(
    issuer.options,
    "DELETE",
    held.registration_client_uri as string,
    held.registration_access_token,
  );
}

export function clientFor(
  issuer: Issuer,
  held: Registration,
  key?: Key,
  dpop?: Key,
): Client {
  return new Client({
    issuer,
    id: held.client_id,
    secret: held.client_secret,
    method: held.token_endpoint_auth_method,
    key,
    dpop,
  });
}

function owned(issuer: Issuer, held: Registration | undefined): void {
  if (!held?.client_id) {
    throw new Error("masks: the registration names no client_id");
  }

  if (!held.registration_client_uri || !held.registration_access_token) {
    throw new Error(
      "masks: the registration holds no registration_client_uri and registration_access_token",
    );
  }

  issuer.sameOrigin(held.registration_client_uri);
}

function kept(held: Registration, fresh: Registration): Registration {
  return {
    ...fresh,
    client_secret: fresh.client_secret ?? held.client_secret,
    client_secret_expires_at: fresh.client_secret
      ? fresh.client_secret_expires_at
      : held.client_secret_expires_at,
    registration_access_token:
      fresh.registration_access_token ?? held.registration_access_token,
    registration_client_uri:
      fresh.registration_client_uri ?? held.registration_client_uri,
  };
}
