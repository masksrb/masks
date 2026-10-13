# Ruby SDK to-do

## Masks::Client

- The DPoP nonce retry has only run against the fake issuer, because masks does not send `DPoP-Nonce`.

## Masks::Rails

- The session sits close to the 4 KB cookie limit when a person belongs to organizations, because it holds the access token, the avatars, and the organizations. A larger access token overflows `:cookie_store` with `ActionDispatch::Cookies::CookieOverflow`. Go, Node, and Python split a large session across several cookies.
