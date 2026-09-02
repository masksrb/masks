const KEY = "masks:manage:client";

export const SCOPE = ["openid", "profile", "email", "masks:manage"];

function held(issuer) {
  try {
    return JSON.parse(localStorage.getItem(KEY) || "null")?.[issuer] || null;
  } catch {
    return null;
  }
}

function keep(issuer, clientId) {
  const all = JSON.parse(localStorage.getItem(KEY) || "{}");

  all[issuer] = clientId;
  localStorage.setItem(KEY, JSON.stringify(all));
}

export function clientId(boot) {
  return held(boot.issuer);
}

export function forget(boot) {
  const all = JSON.parse(localStorage.getItem(KEY) || "{}");

  delete all[boot.issuer];
  localStorage.setItem(KEY, JSON.stringify(all));
}

export function callbackUri(boot) {
  return `${location.origin}${boot.root}/callback`;
}

export function handshakeUrl(boot) {
  const query = new URLSearchParams([
    ["client_name", `Manage ${boot.tenant.name}`],
    ["resource", boot.resource],
    ["scope", SCOPE.join(" ")],
    ["return_to", `${location.origin}${boot.root}`],
    ["token_endpoint_auth_method", "none"],
    ["redirect_uris", callbackUri(boot)],
  ]);

  return `${boot.issuer}/handshake?${query.toString()}`;
}

export async function redeem(boot, token) {
  const response = await fetch(`${boot.issuer}/register`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Accept: "application/json",
      Authorization: `Bearer ${token}`,
    },
    body: JSON.stringify({
      client_name: `Manage ${boot.tenant.name}`,
      redirect_uris: [callbackUri(boot)],
      token_endpoint_auth_method: "none",
    }),
  });

  const body = await response.json().catch(() => ({}));

  if (!response.ok) {
    throw new Error(
      body.error_description || body.error || "registration failed",
    );
  }

  if (body.client_secret) {
    throw new Error(
      "masks issued a secret to a browser, which must never happen",
    );
  }

  keep(boot.issuer, body.client_id);

  return body.client_id;
}
