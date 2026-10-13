# Python SDK to-do

## Security

- A sign-out by `GET` is accepted from a browser that sends neither `Sec-Fetch-Site` nor `Origin`. Every current browser sends `Sec-Fetch-Site`, so only an old browser can be signed out by another site's link.
- The SDK decides whether a store is async from its `get` method alone. A store that mixes sync and async methods fails at its first call instead of when the app starts.
