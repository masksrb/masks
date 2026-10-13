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

## Documentation

[Go apps](https://masks.pages.dev/reference/go/) covers sessions, organizations, privileges,
accepting tokens, delegations, machines, and the client package.
