# Plan

Work that comes after the cleanup job, the browser client's refresh and
sign-out, the account page, and recovery from a lost second factor. Each item
says what a person can do once it lands.

## Plugging in self-hosted apps

- **Forward authentication.** An endpoint Caddy, Traefik, and nginx ask before
  serving an app that has no sign-in of its own.

## Later

- Translations, starting with the manage console, which hard-codes English.
- A logo and colors set from the console.
- Clients and settings declared in a file and applied at boot.
- Token lifetimes set per client.
