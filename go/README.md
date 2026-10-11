# masks for Go

`github.com/masksrb/masks/go` connects a Go service or a machine to masks. It
gets tokens as a client and checks them as an API.

```sh
go get github.com/masksrb/masks/go
```

| Covers | |
| --- | --- |
| Discovery | The issuer's document, checked against the address it was fetched from. |
| Registration | Redeeming an initial access token, then reading, updating, and deleting the client. |
| Client authentication | `client_secret_basic`, `client_secret_post`, `private_key_jwt`, and `none`. |
| Grants | Client credentials, refresh tokens, and the device flow. |
| DPoP | Tokens held to a key, and proofs on every request an `http.Client` sends. |
| Revocation | Access and refresh tokens. |
| Checking tokens | `at+jwt` access tokens, including DPoP-bound ones, in an API or as middleware. |

Signing people in through a browser is left to
[golang.org/x/oauth2](https://pkg.go.dev/golang.org/x/oauth2). See
[Other languages](https://masks.pages.dev/guides/other-languages/#go).

## A machine signs in as itself

A machine keeps two P-256 keys. One signs its client assertions and the other
holds its tokens, so a token copied off the machine is useless without the key.

```go
key, err := masks.GenerateKey()
dpop, err := masks.GenerateKey()

saved, err := json.Marshal(map[string]*masks.Key{"key": key, "dpop": dpop})
```

`json.Marshal` writes the private key, so keep the file readable only by the
machine's service user. `key.JWKS()` is the public half to register.

```go
issuer, err := masks.Discover(ctx, "https://auth.example.com")

client := &masks.Client{Issuer: issuer, ID: clientID, Key: key, DPoP: dpop}

asked := masks.TokenRequest{Scope: []string{"files:read"}, Resource: []string{"https://files.example.com"}}
token, err := client.ClientCredentials(ctx, asked)
```

`client.Method` defaults to `client_secret_basic` when `Secret` is set and to
`private_key_jwt` when `Key` is. When `DPoP` is set, a token that comes back
unbound is refused.

## Enrolling with an initial access token

A manager approves the client in masks, and masks gives out an initial access
token for it. The machine redeems the token once and keeps what comes back.

```go
registration, err := issuer.Register(ctx, masks.ClientMetadata{}, initialAccessToken)
client := issuer.Client(registration, key, dpop)
```

`ReadRegistration`, `UpdateRegistration`, and `DeleteRegistration` manage the
client with its registration access token. They send that token only to the
issuer's own origin.

## Calling an API

`HTTPClient` returns an `http.Client` that fetches and reuses tokens and signs
each request. It sends tokens only to the origins it is given, including after
a redirect.

```go
source := client.CredentialsSource(asked)
api := client.HTTPClient(source, "https://files.example.com")

response, err := api.Get("https://files.example.com/files")
```

A held token goes out as `Authorization: DPoP` with a fresh proof, and a server
that asks for a DPoP nonce is answered once. `RefreshSource` renews a token
with its refresh token and hands each rotated token to a callback to be saved.

## The device flow

A machine with no browser shows a code that a person approves on another
device.

```go
device, err := client.DeviceAuthorization(ctx, masks.TokenRequest{Scope: []string{"openid", "offline_access"}})
fmt.Printf("Open %s and enter %s\n", device.VerificationURI, device.UserCode)

token, err := client.AwaitDevice(ctx, device)
```

`AwaitDevice` polls at the interval masks names, slows down when asked, and
stops when the code expires or `ctx` ends.

## Checking access tokens

```go
verifier := masks.NewVerifier(issuer, "https://files.example.com")
verifier.PublicURL = "https://files.example.com"

http.Handle("/files", verifier.Middleware(files))
```

The verifier checks the signature against the issuer's published keys, the
`at+jwt` type, the issuer, the audience, and the expiry. A DPoP-bound token
needs a proof signed by its key, made for this method and URL, made in the last
minute, and not seen before. Inside the handler, `masks.ClaimsFrom(ctx)` returns
the claims, and `claims.HasScope` checks a scope.

Set `PublicURL` when a proxy sits in front of the API, since a proof names the
address the client used.

## Plain HTTP

Every URL is `https`, except on this machine: `localhost`, a `.localhost` name,
or a loopback address. `masks.AllowPlainHTTP()` lifts that for a private
network.
