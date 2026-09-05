# Changelog

## 0.5.0 — unreleased

First release carrying the consumer half in full. 0.4.0 predates the split described in
`plans/019` and should not be used.

- Discovery, PKCE authorization, token exchange, and token verification against a masks issuer.
- Rack middleware for a resource server.
- A Rails engine, mounted by the consuming app, covering the consumer half of the code flow.
- `rails generate masks:install`.
- `config.store` falls back to a default credential store instead of raising.

## 0.4.0

Withdrawn. An earlier design, published 2024-04-11 and marked "DO NOT USE".
