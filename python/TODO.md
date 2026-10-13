# Python SDK to-do

## Publishing

- PyPI has a pending publisher for `masks-client`. The next release publishes it. After that, change the README's install line to `pip install masks-client`.
- The README does not cover the web integrations, the handshake, or the code flow. The guide at reference/python/index.mdx does.

## masks.web

- `finish_delegation` does not check that the person who finished a connection is the person signed in, as Go and Node do.
- A cookie session larger than about 4 KB raises `ValueError`. Split it across several cookies, as go/web does.
- The avatar is buffered up to 1 MB. Stream it.
- The shared refresh and the memory of seen logout tokens work within one process only. Add stores several processes can share.

## Security

- The security review did not finish `web/credentials.py`.

## Testing

- FastAPI has run against a live masks: the handshake, Reconnect, sign-in, a privilege step-up, a token at the API, a shared refresh, and signing out everywhere, with cookie and async server sessions. Back-channel logout has not, since masks in Docker cannot reach the app on the host.
- Django and Flask have not run against a live masks.
