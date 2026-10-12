# Ruby SDK to-do

## Signing out

- Go, JavaScript, and Python name a `post_logout_redirect_uri` in the handshake and return to `/auth/logout/return`. masks must register that address from the handshake for their sign-out everywhere to work. Masks::Rails still returns through the handshake callback. Move it to `/logout/return`, then stop registering the handshake callback as a post-logout address.
- Fold `masks_logout_url` into `masks_sign_out_upstream`, so there is one entry point.
- Send the remaining raw `after_sign_out` redirects in sessions_controller.rb and handshakes_controller.rb through `masks_after_sign_out_path`.
- `Masks::Client::Handshake` should leave out `backchannel_logout_uri` when the issuer does not advertise `backchannel_logout_supported`, so `Configuration#backchannel_logout_uri_for` no longer needs that rule.

## Masks::Client

- The DPoP nonce retry has only run against the fake issuer, because masks does not send `DPoP-Nonce`.
- `HTTP.fetch`, which the avatar proxy uses, has the scheme check but no size cap.
