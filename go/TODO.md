# Go SDK to-do

## Testing

- go/web ran against a live masks on 2026-10-12. Two processes sat behind one proxy, shared `masks.json`, and kept their sessions and `Store` in Redis through `redisstore`. The run covered the handshake, Connect again, sign-in with an organization, a privilege step-up, a session token at `Protect` and `Either`, a shared refresh, signing out everywhere, a back-channel logout, and Disconnect.
  - Four requests with one expired token, split across both processes, made one refresh. masks rotated the refresh token once.
  - After Disconnect, the other process also sent the browser to the handshake, since it read `masks.json` again.
  - The back-channel logout reached the app through a forwarder inside the masks containers, since masks in Docker cannot reach the host's `localhost`.
- A DPoP-bound token has not reached `Protect` live. The app's own client is not registered for `client_credentials`, so the run needs a machine client enrolled through a namespace.
- The avatar proxy answered 404 live, since the test person had no photo. A photo has not been proxied live.
