# masks for Go

`github.com/masksrb/masks/go` connects a Go app, service, or machine to masks.
It signs people in, gets tokens as a client, and checks them as an API.
`github.com/masksrb/masks/go/web` builds a web app's sign-in on it, with routes,
a sealed session, and middleware for `net/http`. See
[Go apps](https://masks.pages.dev/guides/go/) for the web integration.

```sh
go get github.com/masksrb/masks/go
```

| Covers | |
| --- | --- |
| Discovery | The issuer's document, checked against the address it was fetched from. |
| Handshake | masks' own registration for an app, approved in the browser and redeemed server to server. |
| Signing people in | The code flow with PKCE, state, nonce, the `iss` answer, and a checked ID token, then userinfo and signing out at the issuer. |
| Registration | Redeeming an initial access token, then reading, updating, and deleting the client. |
| Enrollment | An app asking for initial access tokens for its machines, and unenrolling them. |
| Client authentication | `client_secret_basic`, `client_secret_post`, `private_key_jwt`, and `none`. |
| Grants | The authorization code, client credentials, refresh tokens, the device flow, and token exchange. |
| Delegation | Connecting a person's account at a provider and getting its token later. |
| Logout | Checking a back-channel logout token. |
| DPoP | Tokens held to a key, and proofs on every request an `http.Client` sends. |
| Revocation | Access and refresh tokens. |
| Introspection | Asking the issuer whether a token is active and what it grants. |
| Checking tokens | `at+jwt` access tokens, including DPoP-bound ones, in an API or as middleware, with a shared store of seen proofs. |

## A web app signs people in

```go
app, err := web.New(web.Config{
	Issuer:   "https://auth.example.com",
	Resource: "https://app.example.com",
	Secret:   []byte(os.Getenv("SESSION_SECRET")),
})

mux.Handle("/auth/", app.Handler())
mux.Handle("/settings", app.Require()(settings))
```

Open `/auth/handshake` once to connect the app. `web.PersonFrom(r.Context())`
returns the signed-in person. The [Go apps](https://masks.pages.dev/guides/go/)
guide covers organizations, privileges, sessions, tokens, and delegations.

## The code flow without go/web

```go
client := issuer.Client(registration, nil, nil)
client.RedirectURI = "https://app.example.com/callback"

started, err := client.AuthCodeURL(masks.AuthRequest{Organization: "acme"})
```

Keep `started` (its `State`, `Nonce`, and `Verifier`) where only this browser
can reach it, and send the browser to `started.URL`. On the callback:

```go
signed, err := client.Complete(ctx, r.URL.Query(), started)
profile, err := client.UserInfo(ctx, signed.Token)
```

`Complete` refuses another `state`, another `iss`, and an ID token with another
audience or nonce. `EndSessionURL` builds the address that signs the person out
of masks.

## The handshake

```go
handshake := &masks.Handshake{
	Issuer:       issuer,
	Name:         "Catalog",
	Resource:     "https://app.example.com",
	RedirectURIs: []string{"https://app.example.com/callback"},
	ReturnTo:     "https://app.example.com/handshake/callback",
	Scope:        []string{"openid", "profile", "email", "offline_access"},
}

target, state, err := handshake.Start()
```

Keep `state` with the browser and send it to `target`. When masks sends it back
to `ReturnTo`, `handshake.Complete(ctx, r.URL.Query(), state)` registers the app
and returns its registration with a client secret. Every URL shares the
resource's origin.

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

A manager approves the client in masks, or an app enrolls the machine, and
masks gives out an initial access token for it. The machine redeems the token
once and keeps what comes back.

```go
registration, err := issuer.Register(ctx, masks.ClientMetadata{}, initialAccessToken)
client := issuer.Client(registration, key, dpop)
```

`ReadRegistration`, `UpdateRegistration`, and `DeleteRegistration` manage the
client with its registration access token. They send that token only to the
issuer's own origin.

## Enrolling machines as an app

An approved app that has claimed a namespace asks for an initial access token
for each machine it installs. It authenticates the same way it does at the
token endpoint.

```go
enrollment, err := app.Enroll(ctx, masks.EnrollmentRequest{
	Scope:    []string{"xixo:agent"},
	Name:     "nas",
	Lifetime: 15 * time.Minute,
})
```

Each scope falls under one of the app's namespaces. The token lasts from a
minute to an hour, 15 minutes by default, and is spent the first time a
machine registers with it. Hand `enrollment.InitialAccessToken` to the machine,
which passes it to `issuer.Register`.

```go
err := app.Unenroll(ctx, machineClientID)
```

`Unenroll` archives the machine and revokes every token it holds. Unenrolling
a machine twice succeeds both times. A client the app did not enroll answers
with an `*masks.Error` whose `Status` is `404`.

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

## Exchanging a token

`Exchange` trades a token for another one with fewer scopes, another audience,
or a shorter lifetime.

```go
narrowed, err := client.Exchange(ctx, masks.ExchangeRequest{
	SubjectToken: token.AccessToken,
	Scope:        []string{"files:read"},
	Resource:     []string{"https://files.example.com"},
	Lifetime:     5 * time.Minute,
})
```

`SubjectTokenType` and `ActorTokenType` default to an access token. An
`ActorToken` puts the party acting for the subject in the new token's `act`
claim. When `DPoP` is set, the
request carries a proof, a subject token held to that key is accepted, and the
new token comes back held to the same key. An answer whose
`issued_token_type` differs from the one asked for is refused.

Asking for `masks.TokenTypeUpstreamAccessToken`, with the connection's id in
`Audience`, returns the upstream provider's own token for a delegation. That
token is a Bearer token even when the client holds a DPoP key.

## Delegations

```go
started, err := client.StartDelegation("google", masks.AuthRequest{})
connected, err := client.FinishDelegation(ctx, r.URL.Query(), started)

upstream, err := client.UpstreamToken(ctx, connected.Secret, connected.Connection)
```

`client.RedirectURI` is the address the provider's answer comes back to. Save
`connected.Secret`, and then each `upstream.Secret`, before anything else, since
each call replaces it. A `*masks.DelegationError` carries the replacement even
when the call fails after the refresh.

## Introspecting a token

```go
introspected, err := client.Introspect(ctx, token, "access_token")

if introspected.HasScope("files:read") {
	serve()
}
```

masks describes a token to the client it was issued to and to an approved
client whose resources include one of the token's audiences. Every other token comes back inactive. An inactive
answer, or one whose `exp` has passed, returns an `Introspection` with every
field empty, and `HasScope` is false whenever the token is inactive.

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

A verifier remembers the proofs it has seen in its own process. When an API
runs as several processes, set `Replay` to a `masks.ReplayStore` they share.
`First` answers true only the first time it sees a key. A store backed by
Redis sets the key only when it is absent:

```go
verifier.Replay = masks.ReplayStoreFunc(func(ctx context.Context, key string, expiresIn time.Duration) (bool, error) {
	return redis.SetNX(ctx, "dpop:"+key, 1, expiresIn).Result()
})
```

An error from the store refuses the request with `masks.ErrReplayStore`, and
the middleware answers `503`. A token that fails its checks answers `401`
with a challenge.

## Plain HTTP

Every URL is `https`, except on this machine: `localhost`, a `.localhost` name,
or a loopback address. `masks.AllowPlainHTTP()` lifts that for a private
network.
