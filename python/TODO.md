# Python SDK to-do

## Publishing

- PyPI has a pending publisher for `masks-client`. The next release publishes it. After that, change the README's install line to `pip install masks-client`.
- The README does not cover the web integrations, the handshake, or the code flow. The guide at guides/python.mdx does.

## masks.web

- `finish_delegation` does not check that the person who finished a connection is the person signed in, as Go and Node do.
- A cookie session larger than about 4 KB raises `ValueError`. Split it across several cookies, as go/web does.
- The avatar is buffered up to 1 MB. Stream it.
- The shared refresh and the memory of seen logout tokens work within one process only. Add stores several processes can share.
- Server-side session stores are synchronous only. Add an async store for FastAPI.

## Security

- Store the issuer in the session and forget a session from another issuer, as go/web does. This matters when one origin serves several issuers.
- The security review did not finish the Flask and FastAPI adapters or `web/credentials.py`.

## Testing

- Under `pytest -W error`, collection fails on a Starlette TestClient deprecation warning about `httpx2`.
- Nothing has run against a live masks. Every test uses a fake issuer.
