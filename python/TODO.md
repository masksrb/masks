# Python SDK to-do

## Testing

- FastAPI, Flask, and Django have run against a live masks: the handshake, Reconnect, sign-in, a privilege step-up, a token at the API, a shared refresh across concurrent requests, and signing out everywhere. FastAPI also ran with an async server session store, and Django ran under gunicorn with three workers sharing a `RedisStore`.
- Back-channel logout ran live for FastAPI, Flask, and Django on 2026-10-13, against a throwaway masks reached through a forwarder inside its containers. Signing out at masks sent each app a logout token through masks' worker, and all three signed the person out. A logout token sent twice got `400` the second time. A logout token that named only the subject signed out that subject's session.

## Security

- A sign-out by `GET` is accepted from a browser that sends neither `Sec-Fetch-Site` nor `Origin`. Every current browser sends `Sec-Fetch-Site`, so only an old browser can be signed out by another site's link.
- The SDK decides whether a store is async from its `get` method alone. A store that mixes sync and async methods fails at its first call instead of when the app starts.
