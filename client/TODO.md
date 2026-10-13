# Ruby SDK to-do

## Masks::Client

- The DPoP nonce retry has only run against the fake issuer, because masks does not send `DPoP-Nonce`.

## Masks::Rails

- A sign-out by `GET` is accepted from a browser that sends neither `Sec-Fetch-Site` nor `Origin`. Every current browser sends `Sec-Fetch-Site`, so only an old browser can be signed out by another site's link.
