package masks

import (
	"context"
	"errors"
	"net/http"
	"net/url"
	"strings"
	"testing"
	"time"
)

var unfollowed = &http.Client{CheckRedirect: func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse }}

func visit(t *testing.T, target string) url.Values {
	t.Helper()

	response, err := unfollowed.Get(target)
	if err != nil {
		t.Fatal(err)
	}
	response.Body.Close()

	if response.StatusCode != http.StatusFound {
		t.Fatalf("%s answered %d", target, response.StatusCode)
	}

	location, err := url.Parse(response.Header.Get("Location"))
	if err != nil {
		t.Fatal(err)
	}

	return location.Query()
}

func shookHands(t *testing.T, held *fake) *Client {
	t.Helper()

	issuer := discovered(t, held)
	handshake := &Handshake{
		Issuer:       issuer,
		Name:         "Catalog",
		Resource:     "https://app.example",
		RedirectURIs: []string{"https://app.example/auth/callback"},
		ReturnTo:     "https://app.example/auth/handshake/callback",
		Scope:        []string{"openid", "profile", "email", "offline_access", "organization"},

		PostLogoutRedirectURI: "https://app.example/auth/logout/return",
		BackchannelLogoutURI:  "https://app.example/auth/logout/backchannel",
	}

	target, state, err := handshake.Start()
	if err != nil {
		t.Fatal(err)
	}

	registration, err := handshake.Complete(context.Background(), visit(t, target), state)
	if err != nil {
		t.Fatal(err)
	}

	client := issuer.Client(registration, nil, nil)
	client.RedirectURI = "https://app.example/auth/callback"

	return client
}

func TestAHandshakeRegistersTheAppWithASecret(t *testing.T) {
	held := newFake(t)
	client := shookHands(t, held)

	asked := held.handshake
	if asked.Get("resource") != "https://app.example" || asked["redirect_uris"][0] != "https://app.example/auth/callback" ||
		asked.Get("token_endpoint_auth_method") != "client_secret_basic" || !strings.Contains(asked.Get("scope"), "organization") ||
		asked.Get("post_logout_redirect_uri") != "https://app.example/auth/logout/return" || asked.Has("backchannel_logout_uri") {
		t.Fatalf("unexpected handshake %v", asked)
	}

	if client.ID == "" || client.Secret == "" || client.method() != ClientSecretBasic {
		t.Fatalf("unexpected client %+v", client)
	}
}

func TestAHandshakeRefusesWhatItDidNotStart(t *testing.T) {
	held := newFake(t)
	issuer := discovered(t, held)
	handshake := &Handshake{
		Issuer: issuer, Name: "Catalog", Resource: "https://app.example", Scope: []string{"openid"},
		RedirectURIs: []string{"https://app.example/auth/callback"}, ReturnTo: "https://app.example/auth/handshake/callback",
	}

	target, state, err := handshake.Start()
	if err != nil {
		t.Fatal(err)
	}

	returned := visit(t, target)

	cases := map[string]func(url.Values) (url.Values, string){
		"another state": func(held url.Values) (url.Values, string) { return held, "other" },
		"another issuer": func(held url.Values) (url.Values, string) {
			held.Set("iss", "https://elsewhere.example")
			return held, state
		},
		"no token": func(held url.Values) (url.Values, string) {
			held.Del("initial_access_token")
			return held, state
		},
	}

	for name, change := range cases {
		t.Run(name, func(t *testing.T) {
			changed, kept := change(url.Values{"state": {returned.Get("state")}, "iss": {returned.Get("iss")}, "initial_access_token": {returned.Get("initial_access_token")}})

			if _, err := handshake.Complete(context.Background(), changed, kept); err == nil {
				t.Fatal("it was accepted")
			}
		})
	}

	held.declined = true
	target, state, _ = handshake.Start()

	if _, err := handshake.Complete(context.Background(), visit(t, target), state); !HasCode(err, "access_denied") {
		t.Fatalf("expected access_denied, got %v", err)
	}

	for _, change := range []func(*Handshake){
		func(held *Handshake) { held.ReturnTo = "https://elsewhere.example/callback" },
		func(held *Handshake) { held.PostLogoutRedirectURI = "https://elsewhere.example/bye" },
	} {
		elsewhere := *handshake
		change(&elsewhere)

		if _, _, err := elsewhere.Start(); !is[*Foreign](err) {
			t.Fatalf("expected a URL on another origin to be refused, got %v", err)
		}
	}

	issuer.Metadata.BackchannelLogoutSupported = true
	handshake.BackchannelLogoutURI = "https://app.example/auth/logout/backchannel"
	target, _, _ = handshake.Start()

	if parsed, _ := url.Parse(target); parsed.Query().Get("backchannel_logout_uri") != handshake.BackchannelLogoutURI {
		t.Fatalf("an issuer with back-channel logout was not given the URI: %s", target)
	}
}

func TestSigningInWithTheCodeFlow(t *testing.T) {
	held := newFake(t)
	client := shookHands(t, held)

	started, err := client.AuthCodeURL(AuthRequest{
		Scope:        []string{"openid", "profile", "offline_access", "organization"},
		Resource:     []string{"https://app.example"},
		Organization: " ACME ",
	})
	if err != nil {
		t.Fatal(err)
	}

	returned := visit(t, started.URL)

	if held.asked.Get("organization") != "acme" || held.asked.Get("nonce") != started.Nonce || held.asked.Get("resource") != "https://app.example" {
		t.Fatalf("unexpected authorization request %v", held.asked)
	}

	signed, err := client.Complete(context.Background(), returned, started)
	if err != nil {
		t.Fatal(err)
	}

	identity := signed.Identity
	if identity.Subject != "ada" || identity.Organization.Key != "acme" || identity.Tenant.Subdomain != "acme" || identity.SessionID != "sid-ada" {
		t.Fatalf("unexpected identity %+v", identity)
	}

	if identity.Photo() != held.url()+"/avatars/ada/identicon" {
		t.Fatalf("unexpected photo %q", identity.Photo())
	}

	var name string
	if !identity.Claim("name", &name) || name != "Ada Lovelace" {
		t.Fatalf("the raw claims lost the name: %v", identity.Raw)
	}

	if _, err := client.Complete(context.Background(), returned, started); !HasCode(err, "invalid_grant") {
		t.Fatalf("expected a spent code to be refused, got %v", err)
	}

	profile, err := client.UserInfo(context.Background(), signed.Token)
	if err != nil {
		t.Fatal(err)
	}

	merged, err := identity.Merged(profile, "orgs", "name")
	if err != nil {
		t.Fatal(err)
	}

	if len(merged.Organizations) != 2 || merged.Subject != "ada" || merged.Organization.Key != "acme" {
		t.Fatalf("unexpected merge %+v", merged)
	}

	kept, err := merged.Kept("sub", "orgs")
	if err != nil || kept.Name != "" || len(kept.Organizations) != 2 {
		t.Fatalf("unexpected kept identity %+v %v", kept, err)
	}
}

func TestACallbackIsCheckedBeforeTheCodeIsSpent(t *testing.T) {
	held := newFake(t)
	client := shookHands(t, held)

	cases := map[string]func(url.Values, *Authorization){
		"another state":  func(held url.Values, _ *Authorization) { held.Set("state", "other") },
		"another issuer": func(held url.Values, _ *Authorization) { held.Set("iss", "https://elsewhere.example") },
		"no issuer":      func(held url.Values, _ *Authorization) { held.Del("iss") },
		"another nonce":  func(_ url.Values, pending *Authorization) { pending.Nonce = "other" },
		"another verifier": func(_ url.Values, pending *Authorization) {
			pending.Verifier = strings.Repeat("a", 64)
		},
	}

	for name, change := range cases {
		t.Run(name, func(t *testing.T) {
			started, err := client.AuthCodeURL(AuthRequest{})
			if err != nil {
				t.Fatal(err)
			}

			returned := visit(t, started.URL)
			change(returned, started)

			if _, err := client.Complete(context.Background(), returned, started); err == nil {
				t.Fatal("it was accepted")
			}
		})
	}

	held.declined = true
	started, _ := client.AuthCodeURL(AuthRequest{})

	if _, err := client.Complete(context.Background(), visit(t, started.URL), started); !HasCode(err, "access_denied") {
		t.Fatalf("expected access_denied, got %v", err)
	}
}

func TestAnIDTokenForAnotherClientIsRefused(t *testing.T) {
	held := newFake(t)
	client := shookHands(t, held)

	claims := map[string]any{
		"iss": held.url(), "sub": "ada", "aud": "someone-else",
		"exp": time.Now().Add(time.Minute).Unix(), "iat": time.Now().Unix(),
	}

	if _, err := client.VerifyIDToken(context.Background(), held.issue(claims, "JWT")); !is[*InvalidToken](err) {
		t.Fatalf("expected ErrInvalidToken, got %v", err)
	}

	claims["aud"] = []string{client.ID, "someone-else"}

	if _, err := client.VerifyIDToken(context.Background(), held.issue(claims, "JWT")); !is[*InvalidToken](err) {
		t.Fatalf("a token with several audiences and no azp was accepted: %v", err)
	}

	claims["aud"] = client.ID

	if _, err := client.VerifyIDToken(context.Background(), held.issue(claims, accessTokenType)); !is[*InvalidToken](err) {
		t.Fatalf("an access token was accepted as an ID token: %v", err)
	}

	if _, err := client.VerifyIDToken(context.Background(), held.issue(claims, "JWT")); err != nil {
		t.Fatalf("a good ID token was refused: %v", err)
	}
}

func TestEndingTheSessionAtTheIssuer(t *testing.T) {
	held := newFake(t)
	client := shookHands(t, held)

	target, err := client.EndSessionURL(EndSession{PostLogoutRedirectURI: "https://app.example/auth/logout/return", State: "bye"})
	if err != nil {
		t.Fatal(err)
	}

	returned := visit(t, target)

	if returned.Get("state") != "bye" || held.ended.Get("client_id") != client.ID {
		t.Fatalf("unexpected %v %v", returned, held.ended)
	}
}

func TestALogoutTokenNamesTheSession(t *testing.T) {
	held := newFake(t)
	client := shookHands(t, held)

	good := map[string]any{
		"iss": held.url(), "aud": client.ID, "iat": time.Now().Unix(), "exp": time.Now().Add(2 * time.Minute).Unix(),
		"jti": "logout-1", "sid": "sid-ada", "events": map[string]any{BackchannelLogoutEvent: map[string]any{}},
	}

	logout, err := client.VerifyLogoutToken(context.Background(), held.issue(good, "logout+jwt"))
	if err != nil {
		t.Fatal(err)
	}

	if logout.SessionID != "sid-ada" {
		t.Fatalf("unexpected %+v", logout)
	}

	changed := func(name string, value any) map[string]any {
		held := map[string]any{}
		for key, kept := range good {
			held[key] = kept
		}

		if value == nil {
			delete(held, name)
		} else {
			held[name] = value
		}

		return held
	}

	cases := map[string]string{
		"an ID token":     held.issue(good, "JWT"),
		"a nonce":         held.issue(changed("nonce", "n"), "logout+jwt"),
		"no event":        held.issue(changed("events", map[string]any{}), "logout+jwt"),
		"nobody":          held.issue(changed("sid", nil), "logout+jwt"),
		"another client":  held.issue(changed("aud", "other"), "logout+jwt"),
		"no jti":          held.issue(changed("jti", nil), "logout+jwt"),
		"no exp":          held.issue(changed("exp", nil), "logout+jwt"),
		"expired":         held.issue(changed("exp", time.Now().Add(-2*time.Minute).Unix()), "logout+jwt"),
		"from the future": held.issue(changed("iat", time.Now().Add(time.Hour).Unix()), "logout+jwt"),
	}

	for name, token := range cases {
		t.Run(name, func(t *testing.T) {
			if _, err := client.VerifyLogoutToken(context.Background(), token); err == nil {
				t.Fatal("it was accepted")
			}
		})
	}
}

func TestADelegationConnectsAnAccountAndReleasesItsToken(t *testing.T) {
	held := newFake(t)
	client := shookHands(t, held)

	started, err := client.StartDelegation("google", AuthRequest{Prompt: "login"})
	if err != nil {
		t.Fatal(err)
	}

	if held.asked != nil {
		t.Fatal("the delegation was started before the browser went")
	}

	returned := visit(t, started.URL)

	if held.asked.Get("scope") != "openid offline_access masks:delegate:google" || held.asked.Get("prompt") != "login" {
		t.Fatalf("unexpected %v", held.asked)
	}

	connected, err := client.FinishDelegation(context.Background(), returned, started)
	if err != nil {
		t.Fatal(err)
	}

	if connected.Connection != "connection-google" || connected.Secret == "" || connected.Subject != "ada" {
		t.Fatalf("unexpected %+v", connected)
	}

	upstream, err := client.UpstreamToken(context.Background(), connected.Secret, connected.Connection)
	if err != nil {
		t.Fatal(err)
	}

	if !upstream.Valid() || upstream.Secret == connected.Secret {
		t.Fatalf("unexpected %+v", upstream)
	}

	_, err = client.UpstreamToken(context.Background(), connected.Secret, connected.Connection)

	var refused *DelegationRefused
	if !errors.As(err, &refused) || refused.Code != "invalid_grant" {
		t.Fatalf("expected the spent secret to be refused, got %v", err)
	}

	held.upstreamDown = true

	_, err = client.UpstreamToken(context.Background(), upstream.Secret, connected.Connection)
	var busy *DelegationUnavailable
	if !errors.As(err, &busy) || busy.Secret == "" || busy.Secret == upstream.Secret {
		t.Fatalf("a failed exchange lost the rotated secret: %v", err)
	}
}

func TestMaxAgeRefusesASignInThatIsTooOld(t *testing.T) {
	held := newFake(t)
	client := shookHands(t, held)

	for _, check := range []struct {
		name     string
		authTime int64
		accepted bool
	}{
		{"just now", time.Now().Unix(), true},
		{"an hour ago", time.Now().Add(-time.Hour).Unix(), false},
		{"never said", 0, false},
	} {
		t.Run(check.name, func(t *testing.T) {
			held.lock.Lock()
			held.authTime = check.authTime
			held.lock.Unlock()

			started, err := client.AuthCodeURL(AuthRequest{MaxAge: 5 * time.Minute})
			if err != nil {
				t.Fatal(err)
			}

			_, err = client.Complete(context.Background(), visit(t, started.URL), started)
			if (err == nil) != check.accepted {
				t.Fatalf("a sign-in from %s answered %v", check.name, err)
			}
		})
	}
}
