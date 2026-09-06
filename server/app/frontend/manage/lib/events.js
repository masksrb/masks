const SAID = {
  "session.started": "Signed in",
  "session.ended": "Signed out",
  "session.revoked": "Session revoked",
  "login.refused": "Sign-in refused",
  "login.throttled": "Sign-in throttled",

  "account.created": "Account created",
  "invitation.sent": "Invitation sent",
  "invitation.accepted": "Invitation accepted",

  "password.changed": "Password changed",
  "password.reset_requested": "Password reset requested",
  "password.reset_completed": "Password reset",

  "email.verification_sent": "Confirmation sent",
  "email.verified": "Email confirmed",

  "passkey.added": "Passkey added",
  "passkey.removed": "Passkey removed",
  "backup_codes.generated": "Backup codes generated",
  "backup_code.spent": "Backup code used",
  "authenticator.disabled": "Authenticator disabled",

  "device.trusted": "Device trusted",
  "device.named": "Device renamed",
  "device.forgotten": "Device signed out",
  "device.blocked": "Device blocked",
  "device.unblocked": "Device unblocked",

  "avatar.uploaded": "Photo uploaded",
  "avatar.removed": "Photo removed",

  "consent.granted": "Consent granted",
  "connection.linked": "Provider connected",
  "connection.unlinked": "Provider disconnected",

  "actor.created": "Person added",
  "actor.updated": "Profile edited",
  "actor.deleted": "Person deleted",
  "actor.scopes_changed": "Scopes changed",
  "actor.signed_out": "Signed out everywhere",

  "client.registered": "Client registered",
  "client.approved": "Client approved",
  "client.updated": "Client edited",
  "client.archived": "Client archived",
  "client.secret_rotated": "Client secret rotated",

  "token.revoked": "Token revoked",
  "refresh.reused": "Refresh token replayed",

  "signing_key.staged": "Signing key staged",
  "signing_key.rotated": "Signing key rotated",
  "signing_key.activated": "Signing key activated",
  "signing_key.discarded": "Signing key discarded",

  "namespace.released": "Namespace released",
  "provider.created": "Provider added",
  "provider.updated": "Provider edited",
  "provider.archived": "Provider archived",
  "tenant.updated": "Settings changed",
};

const GRAVE = new Set([
  "login.refused",
  "login.throttled",
  "refresh.reused",
  "device.blocked",
  "actor.deleted",
  "authenticator.disabled",
]);

const NOTABLE = new Set([
  "password.changed",
  "password.reset_completed",
  "actor.scopes_changed",
  "client.secret_rotated",
  "signing_key.rotated",
  "signing_key.activated",
  "backup_code.spent",
  "connection.unlinked",
]);

export function said(action) {
  return SAID[action] ?? action;
}

export function tone(action) {
  if (GRAVE.has(action)) return "bad";
  if (NOTABLE.has(action)) return "watch";

  return "plain";
}

export function detailed(details) {
  return Object.entries(details ?? {})
    .filter(([, value]) => value !== null && value !== "" && !(Array.isArray(value) && !value.length))
    .map(([key, value]) => [key.replace(/_/g, " "), phrase(value)]);
}

function phrase(value) {
  if (Array.isArray(value)) return value.join(" ");
  if (typeof value === "boolean") return value ? "yes" : "no";

  return String(value);
}
