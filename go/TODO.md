# Go SDK to-do

## Security

- go/web refuses a cross-site sign-out by `Sec-Fetch-Site`, or by `Origin` when that header is missing. A browser that sends neither on a cross-site `GET`, such as Safari before 16.4, can still be made to sign a person out of the app with an image tag. Only sign-outs by `POST` would close that, which changes the routes.
- `Verifier` compares a proof's `htm` to the request method without regard to case. RFC 9449 compares them exactly. No client masks knows of sends a lowercase method.

## Testing

- go/web ran against a live masks on 2026-10-12. Two processes sat behind one proxy, shared `masks.json`, and kept their sessions and `Store` in Redis through `redisstore`. The run covered the handshake, Connect again, sign-in with an organization, a privilege step-up, a session token at `Protect` and `Either`, a shared refresh, signing out everywhere, a back-channel logout, and Disconnect.
  - Four requests with one expired token, split across both processes, made one refresh. masks rotated the refresh token once.
  - After Disconnect, the other process also sent the browser to the handshake, since it read `masks.json` again.
  - The back-channel logout reached the app through a forwarder inside the masks containers, since masks in Docker cannot reach the host's `localhost`.
- A DPoP-bound token reached `Protect` live on 2026-10-13. The app, holding the `catalog:` namespace, enrolled a machine with `Enroll`. The machine registered its own key and got a DPoP token through `client_credentials`. Through the same two processes and Redis:
  - The client's signing transport was accepted on both processes, and so was `Either`.
  - A proof used twice was refused on the other process.
  - The token presented as Bearer, a proof for another URL, and a proof by another key were all refused.
  - The app's introspection saw the token, and `Unenroll` ended the machine's client.
- The avatar proxy answered 404 live, since the test person had no photo. A photo has not been proxied live.
