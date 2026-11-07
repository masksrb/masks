# masks for Go

`github.com/masksrb/masks/go` connects a Go app, service, or machine to a masks server. It signs
people in, gets tokens as a client, and checks them in an API. `github.com/masksrb/masks/go/web`
builds a web app's sign-in on it for `net/http`, with routes, a sealed session, and middleware.

It needs Go 1.25 or later.

```sh
go get github.com/masksrb/masks/go
```

## Sign people in to a web app

```go
app, err := web.New(web.Config{
	Issuer:   "https://auth.example.com",
	Resource: "https://app.example.com",
	Secret:   []byte(os.Getenv("SESSION_SECRET")),
})
if err != nil {
	log.Fatal(err)
}

mux := http.NewServeMux()
mux.Handle("/auth/", app.Handler())
mux.Handle("/settings", app.Require()(settings))
```

`SESSION_SECRET` is at least 32 random bytes. Open `/auth/handshake` once to connect the app to
masks. Inside a handler, `web.ActorFrom(r.Context())` returns the person signed in.

## Testing your app

`github.com/masksrb/masks/go/masktest` is a fake masks server for tests. It serves discovery and
keys, registers clients, signs a person in through the code flow, rotates refresh tokens, and mints
access and logout tokens the SDK verifies. The same fake runs this package's own tests.

```go
func TestSigningIn(t *testing.T) {
	fake := masktest.New(t)
	fake.Add("app", &masktest.Client{Secret: "secret", Method: masktest.ClientSecretBasic})

	issuer, err := masks.Discover(context.Background(), fake.URL())
	if err != nil {
		t.Fatal(err)
	}

	client := &masks.Client{Issuer: issuer, ID: "app", Secret: "secret"}
	logout, err := client.VerifyLogoutToken(context.Background(), fake.LogoutToken(map[string]any{"aud": "app", "sid": "sid-ada"}))
	if err != nil {
		t.Fatal(err)
	}

	if logout.SessionID != "sid-ada" {
		t.Fatal(logout)
	}
}
```

`fake.Actor` is the person who signs in, `fake.Declined` turns the next sign-in away, and
`fake.Seen` holds the last form sent to each endpoint.

## Documentation

[Go apps](https://masks.pages.dev/reference/go/) covers sessions, organizations, privileges,
accepting tokens, delegations, machines, and the client package.
