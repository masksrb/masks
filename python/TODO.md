# Python SDK to-do

## Publishing

- PyPI has a pending publisher for `masks-client`. The next release publishes it. After that, change the README's install line to `pip install masks-client`.
- The README does not cover the web integrations, the handshake, or the code flow. The guide at reference/python/index.mdx does.

## Testing

- FastAPI, Flask, and Django have run against a live masks: the handshake, Reconnect, sign-in, a privilege step-up, a token at the API, a shared refresh across concurrent requests, and signing out everywhere. FastAPI also ran with an async server session store, and Django ran under gunicorn with three workers sharing a `RedisStore`. Back-channel logout has not, since masks in Docker cannot reach the app on the host.
