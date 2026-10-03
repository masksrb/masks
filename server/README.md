# masks server

The app that runs the masks provider on its own. It mounts the `masks-server` engine from
[`../engine`](../engine) at `/` with the configuration the container image uses, which is Server
mode in [Rails apps](https://masks.pages.dev/guides/rails/). The provider's models, logins,
policies, jobs, and manage API live in the engine. This app holds what the image needs around it:

```
app/frontend/   Svelte, for the prompts and the manage console
config/         the host app's environments, database, and routes
db/             structure.sql, because schema.rb cannot represent a row-level security policy
Dockerfile      the published image
```

Run it from the repository root with `./dev`. See
[configuration](https://masks.pages.dev/reference/environment/) for every variable it reads, and
`.env.example` for a starting set.

## The database role is not a superuser

A superuser bypasses row-level security, and a table's owner bypasses it unless the table is
`FORCE`d. Either makes every isolation test pass without proving anything.
`db/docker-entrypoint-initdb.d` creates a separate non-superuser role for Rails to connect as.

## Tests

The suites live in `../test`. `./dev test unit integration` runs them in containers, and
`bin/rake test` runs both here when the host has the toolchain.

Isolation is asserted in `test/unit/models/tenant_isolation_test.rb` and
`row_level_security_test.rb`, and enumeration resistance in `login_enumeration_test.rb` beside them.

Rate limits run on `Rails.cache`, which is Solid Cache in every environment, so a limit behaves the
same in a test as in production.
