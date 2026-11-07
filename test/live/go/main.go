package main

import (
	"bufio"
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"net"
	"net/http"
	"net/url"
	"os"
	"slices"
	"strconv"
	"time"

	masks "github.com/masksrb/masks/go"
)

type app struct {
	issuer       *masks.Issuer
	handshake    *masks.Handshake
	state        string
	redirectURI  string
	scope        []string
	signInScope  []string
	registration *masks.Registration
	client       *masks.Client
	pending      *masks.Authorization
	token        *masks.Token
	logouts      chan *masks.LogoutToken
}

func main() {
	port := flag.Int("port", 4414, "")
	bind := flag.String("bind", "127.0.0.1", "")
	flag.Parse()

	held := &app{logouts: make(chan *masks.LogoutToken, 8)}

	listener, err := net.Listen("tcp", net.JoinHostPort(*bind, strconv.Itoa(*port)))
	if err != nil {
		fail(err)
	}

	mux := http.NewServeMux()
	mux.HandleFunc("POST /backchannel", held.backchannel)
	go func() { _ = http.Serve(listener, mux) }()

	answer(map[string]any{"ready": true})

	scanner := bufio.NewScanner(os.Stdin)
	scanner.Buffer(make([]byte, 1<<20), 1<<20)

	for scanner.Scan() {
		asked := map[string]any{}
		if err := json.Unmarshal(scanner.Bytes(), &asked); err != nil {
			answer(map[string]any{"error": err.Error()})
			continue
		}

		step, _ := asked["step"].(string)
		if step == "quit" {
			return
		}

		result, err := held.step(step, asked)
		if err != nil {
			answer(map[string]any{"error": err.Error()})
			continue
		}

		answer(result)
	}
}

func fail(err error) {
	answer(map[string]any{"error": err.Error()})
	os.Exit(1)
}

func answer(value map[string]any) {
	held, _ := json.Marshal(value)
	fmt.Println(string(held))
}

func text(asked map[string]any, name string) string {
	held, _ := asked[name].(string)
	return held
}

func words(asked map[string]any, name string) []string {
	raw, _ := asked[name].([]any)
	held := make([]string, 0, len(raw))

	for _, value := range raw {
		if word, ok := value.(string); ok {
			held = append(held, word)
		}
	}

	return held
}

func query(target string) (url.Values, error) {
	parsed, err := url.Parse(target)
	if err != nil {
		return nil, err
	}

	return parsed.Query(), nil
}

func (a *app) step(step string, asked map[string]any) (map[string]any, error) {
	ctx := context.Background()

	switch step {
	case "handshake":
		return a.startHandshake(ctx, asked)
	case "handshake:complete":
		return a.completeHandshake(ctx, asked)
	case "signin":
		return a.startSignIn(asked)
	case "signin:complete":
		return a.completeSignIn(ctx, asked)
	case "refresh":
		return a.refresh(ctx)
	case "logout":
		return a.logout(asked)
	case "machine":
		return a.machine(ctx, asked)
	}

	return nil, fmt.Errorf("unknown step %q", step)
}

func (a *app) startHandshake(ctx context.Context, asked map[string]any) (map[string]any, error) {
	issuer, err := masks.Discover(ctx, text(asked, "issuer"))
	if err != nil {
		return nil, err
	}

	a.issuer = issuer
	a.redirectURI = text(asked, "redirect_uri")
	a.scope = words(asked, "scope")
	a.signInScope = words(asked, "signin_scope")
	a.handshake = &masks.Handshake{
		Issuer:               issuer,
		Name:                 text(asked, "name"),
		Resource:             text(asked, "resource"),
		RedirectURIs:         []string{a.redirectURI},
		ReturnTo:             text(asked, "return_to"),
		Scope:                a.scope,
		BackchannelLogoutURI: text(asked, "backchannel_logout_uri"),
	}

	target, state, err := a.handshake.Start()
	if err != nil {
		return nil, err
	}

	a.state = state

	return map[string]any{"url": target, "state": state}, nil
}

func (a *app) completeHandshake(ctx context.Context, asked map[string]any) (map[string]any, error) {
	returned, err := query(text(asked, "url"))
	if err != nil {
		return nil, err
	}

	registration, err := a.handshake.Complete(ctx, returned, a.state)
	if err != nil {
		return nil, err
	}

	a.registration = registration
	a.client = a.issuer.Client(registration, nil, nil)
	a.client.RedirectURI = a.redirectURI

	return map[string]any{"client_id": registration.ClientID}, nil
}

func (a *app) startSignIn(asked map[string]any) (map[string]any, error) {
	request := masks.AuthRequest{Scope: a.signInScope, Prompt: text(asked, "prompt")}

	if age, ok := asked["max_age"].(float64); ok && age > 0 {
		request.MaxAge = time.Duration(age) * time.Second
	}

	pending, err := a.client.AuthCodeURL(request)
	if err != nil {
		return nil, err
	}

	a.pending = pending

	return map[string]any{"url": pending.URL}, nil
}

func (a *app) completeSignIn(ctx context.Context, asked map[string]any) (map[string]any, error) {
	returned, err := query(text(asked, "url"))
	if err != nil {
		return nil, err
	}

	signed, err := a.client.Complete(ctx, returned, a.pending)
	if err != nil {
		return nil, err
	}

	if signed.Identity == nil {
		return nil, fmt.Errorf("the sign-in came back without an identity")
	}

	a.token = signed.Token

	var amr []string
	if raw, ok := signed.Identity.Raw["amr"]; ok {
		_ = json.Unmarshal(raw, &amr)
	}

	return map[string]any{
		"sub":           signed.Identity.Subject,
		"sid":           signed.Identity.SessionID,
		"auth_time":     signed.Identity.AuthTime,
		"amr":           amr,
		"refresh_token": signed.Token.RefreshToken != "",
		"id_token":      signed.Token.IDToken != "",
	}, nil
}

func (a *app) refresh(ctx context.Context) (map[string]any, error) {
	renewed, err := a.client.Refresh(ctx, a.token.RefreshToken, masks.TokenRequest{})
	if err != nil {
		return nil, err
	}

	rotated := renewed.RefreshToken != "" && renewed.RefreshToken != a.token.RefreshToken &&
		renewed.AccessToken != a.token.AccessToken
	a.token = renewed

	var identity *masks.Identity
	if renewed.IDToken != "" {
		identity, err = a.client.VerifyIDToken(ctx, renewed.IDToken, masks.Expectations{AccessToken: renewed.AccessToken})
	} else {
		identity, err = a.client.UserInfo(ctx, renewed)
	}
	if err != nil {
		return nil, err
	}

	return map[string]any{"rotated": rotated, "sub": identity.Subject}, nil
}

func (a *app) logout(asked map[string]any) (map[string]any, error) {
	timeout := 30.0
	if held, ok := asked["timeout"].(float64); ok {
		timeout = held
	}

	select {
	case received := <-a.logouts:
		return map[string]any{"sid": received.SessionID, "sub": received.Subject}, nil
	case <-time.After(time.Duration(timeout * float64(time.Second))):
		return nil, fmt.Errorf("no logout token arrived")
	}
}

func (a *app) backchannel(response http.ResponseWriter, request *http.Request) {
	if err := request.ParseForm(); err != nil {
		response.WriteHeader(http.StatusBadRequest)
		return
	}

	logout, err := a.client.VerifyLogoutToken(request.Context(), request.PostForm.Get("logout_token"))
	if err != nil {
		fmt.Fprintln(os.Stderr, "go live app:", err)
		response.WriteHeader(http.StatusBadRequest)
		return
	}

	a.logouts <- logout
	response.WriteHeader(http.StatusOK)
}

func (a *app) machine(ctx context.Context, asked map[string]any) (map[string]any, error) {
	scope := text(asked, "scope")

	enrollment, err := a.client.Enroll(ctx, masks.EnrollmentRequest{Scope: []string{scope}, Name: "live machine"})
	if err != nil {
		return nil, err
	}

	key, err := masks.GenerateKey()
	if err != nil {
		return nil, err
	}

	dpop, err := masks.GenerateKey()
	if err != nil {
		return nil, err
	}

	registered, err := a.issuer.Register(ctx, masks.ClientMetadata{
		Name:                    "live machine",
		GrantTypes:              []string{masks.GrantClientCredentials},
		Scope:                   scope,
		TokenEndpointAuthMethod: masks.PrivateKeyJWT,
		JWKS:                    key.JWKS(),
		DPoPBoundAccessTokens:   true,
	}, enrollment.InitialAccessToken)
	if err != nil {
		return nil, err
	}

	machine := a.issuer.Client(registered, key, dpop)

	token, err := machine.ClientCredentials(ctx, masks.TokenRequest{Scope: []string{scope}, Resource: []string{text(asked, "resource")}})
	if err != nil {
		return nil, err
	}

	introspected, err := a.client.Introspect(ctx, token.AccessToken, "")
	if err != nil {
		return nil, err
	}

	jkt := introspected.Confirmation != nil && introspected.Confirmation.Thumbprint == dpop.Thumbprint()

	return map[string]any{
		"client_id": registered.ClientID,
		"bound":     token.Bound(),
		"active":    introspected.Active,
		"scope":     token.Scope,
		"jkt":       jkt,
		"scopes_ok": slices.Contains(introspected.Scopes(), scope),
	}, nil
}
