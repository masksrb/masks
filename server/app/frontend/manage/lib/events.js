const GRAVE = new Set([
  "logout.undelivered",
  "login.refused",
  "login.throttled",
  "refresh.reused",
  "device.blocked",
  "actor.deleted",
  "authenticator.disabled",
  "connection.refused",
  "delegation.refused",
]);

const NOTABLE = new Set([
  "password.changed",
  "password.reset_completed",
  "actor.scopes_changed",
  "actor.suspended",
  "provisioning_token.issued",
  "provisioning_token.revoked",
  "client.secret_rotated",
  "client.logo_refused",
  "signing_key.rotated",
  "signing_key.activated",
  "backup_code.spent",
  "connection.unlinked",
  "consent.revoked",
  "delegation.granted",
  "delegation.revoked",
]);

export function tone(action) {
  if (GRAVE.has(action)) return "bad";
  if (NOTABLE.has(action)) return "watch";

  return "plain";
}

export function detailed(details) {
  return Object.entries(details ?? {})
    .filter(
      ([, value]) =>
        value !== null &&
        value !== "" &&
        !(Array.isArray(value) && !value.length),
    )
    .map(([key, value]) => [key.replace(/_/g, " "), phrase(value)]);
}

function phrase(value) {
  if (Array.isArray(value)) return value.join(" ");
  if (typeof value === "boolean") return value ? "yes" : "no";

  return String(value);
}
