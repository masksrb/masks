# Plan

Work that comes after the cleanup job, the browser client's refresh and
sign-out, the account page, and recovery from a lost second factor. Each item
says what a person can do once it lands.

## Security

- **Decide what support may do to an account.** Support can change a person's
  email, receive the reset link when masks cannot mail them, and generate
  their backup codes. The old address is now mailed when the email changes.
- **The engine protects its own forms.** Account actions rely on the host
  app's `protect_from_forgery` default.

## Plugging in self-hosted apps

- **Groups.** A `groups` claim in the ID token and userinfo, so Grafana,
  Nextcloud, Gitea, and Immich can map people to roles.
- **Who may sign in to each app.** A list of people or groups on a client,
  checked at sign-in.
- **A page of my apps.** The account page links to each app a person may
  use, including apps that start a SAML sign-in.
- **Presets for common apps.** Adding Grafana or Nextcloud fills in the
  redirect URIs, scopes, and claims.
- **Forward authentication.** An endpoint Caddy, Traefik, and nginx ask before
  serving an app that has no sign-in of its own.

## Running masks

- **The only manager can get back in.** A task prints a one-time reset link
  for an account and records an event, and the self-hosting guide says how to
  run it.
- **More than one replica shares its secrets.** A replica started without the
  master key refuses to boot in production, and the self-hosting guide covers
  running several.
- **The master key can be rotated.** The previous key still decrypts, and a
  task re-encrypts every column with the new one.
- **Backup, restore, and upgrade.** The self-hosting guide covers all three
  databases, and `/up` reports failed recurring jobs.
- **A checklist after setup.** The overview lists mail, the first app,
  inviting people, and a domain, and ticks each off.

## Later

- Translations, starting with the manage console, which hard-codes English.
- A logo and colors set from the console.
- Clients and settings declared in a file and applied at boot.
- Token lifetimes set per client.
- Revoking a long chain of refresh tokens in one query.
