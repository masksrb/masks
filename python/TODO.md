# Python SDK to-do

## Publishing

- PyPI has a pending publisher for `masks-client`. The next release publishes it. After that, change the README's install line to `pip install masks-client`.

## Testing

- FastAPI, Flask, and Django have run against a live masks: the handshake, Reconnect, sign-in, a privilege step-up, a token at the API, a shared refresh across concurrent requests, and signing out everywhere. FastAPI also ran with an async server session store, and Django ran under gunicorn with three workers sharing a `RedisStore`. Back-channel logout has not, since masks in Docker cannot reach the app on the host.

## Security

- A sign-out by `GET` is accepted from a browser that sends neither `Sec-Fetch-Site` nor `Origin`. Every current browser sends `Sec-Fetch-Site`, so only an old browser can be signed out by another site's link.
- The SDK decides whether a store is async from its `get` method alone. A store that mixes sync and async methods fails at its first call instead of when the app starts.
