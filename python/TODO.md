# Python SDK to-do

## Publishing

- PyPI has a pending publisher for `masks-client`. The next release publishes it. After that, change the README's install line to `pip install masks-client`.
- The README does not cover the web integrations, the handshake, or the code flow. The guide at guides/python.mdx does.

## masks.web

- `finish_delegation` does not check that the person who finished a connection is the person signed in, as Go and Node do.
- A cookie session larger than about 4 KB raises `ValueError`. Split it across several cookies, as go/web does.
- The avatar is buffered up to 1 MB. Stream it.
- The shared refresh and the memory of seen logout tokens work within one process only. Add stores several processes can share.

## Security

- The security review did not finish the Flask adapter or `web/credentials.py`.

## Testing

- Nothing has run against a live masks. Every test uses a fake issuer.
