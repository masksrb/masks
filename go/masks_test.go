package masks

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

func discovered(t *testing.T, held *fake) *Issuer {
	t.Helper()

	issuer, err := Discover(context.Background(), held.url())
	if err != nil {
		t.Fatal(err)
	}

	return issuer
}

func TestDiscoveryRefusesADocumentNamingAnotherIssuer(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(response http.ResponseWriter, _ *http.Request) {
		writeJSON(response, http.StatusOK, map[string]string{"issuer": "https://elsewhere.example"})
	}))
	defer server.Close()

	if _, err := Discover(context.Background(), server.URL); err == nil || !strings.Contains(err.Error(), "elsewhere") {
		t.Fatalf("expected the issuer mismatch to be refused, got %v", err)
	}
}

func TestPlainHTTPIsAllowedOnlyOnThisMachine(t *testing.T) {
	held := settings{}

	for _, allowed := range []string{"https://id.example", "http://127.0.0.1:3000", "http://masks.localhost:12345", "http://[::1]:80"} {
		if err := held.check(allowed); err != nil {
			t.Errorf("%s: %v", allowed, err)
		}
	}

	for _, refused := range []string{"http://id.example", "http://10.0.0.4", "ftp://id.example", "id.example"} {
		if err := held.check(refused); err == nil {
			t.Errorf("%s was allowed", refused)
		}
	}

	if err := held.check("http://10.0.0.4"); !errors.Is(err, ErrInsecure) {
		t.Errorf("expected ErrInsecure, got %v", err)
	}

	if err := (settings{plainHTTP: true}).check("http://10.0.0.4"); err != nil {
		t.Errorf("AllowPlainHTTP still refused: %v", err)
	}
}

func TestClientCredentialsWithASecret(t *testing.T) {
	for _, method := range []AuthMethod{ClientSecretBasic, ClientSecretPost} {
		t.Run(string(method), func(t *testing.T) {
			held := newFake(t)
			held.add("machine", &fakeClient{secret: "s3cr:et/+", method: method, scope: "files:read"})

			client := &Client{Issuer: discovered(t, held), ID: "machine", Secret: "s3cr:et/+", Method: method}

			token, err := client.ClientCredentials(context.Background(), TokenRequest{})
			if err != nil {
				t.Fatal(err)
			}

			if token.Bound() || token.Scope != "files:read" || !token.Valid() {
				t.Fatalf("unexpected token %+v", token)
			}
		})
	}
}

func TestAWrongSecretIsAnInvalidClient(t *testing.T) {
	held := newFake(t)
	held.add("machine", &fakeClient{secret: "right", method: ClientSecretBasic})

	client := &Client{Issuer: discovered(t, held), ID: "machine", Secret: "wrong"}

	_, err := client.ClientCredentials(context.Background(), TokenRequest{})

	var refused *Error
	if !errors.As(err, &refused) || refused.Code != "invalid_client" || refused.Status != http.StatusUnauthorized {
		t.Fatalf("expected invalid_client, got %v", err)
	}
}

func signedClient(t *testing.T, held *fake) (*Client, *Key) {
	t.Helper()

	key, err := GenerateKey()
	if err != nil {
		t.Fatal(err)
	}

	dpop, err := GenerateKey()
	if err != nil {
		t.Fatal(err)
	}

	jwks := fakeClient{method: PrivateKeyJWT, scope: "files:read"}
	if err := json.Unmarshal(key.JWKS(), &jwks.jwks); err != nil {
		t.Fatal(err)
	}

	held.add("signed", &jwks)

	return &Client{Issuer: discovered(t, held), ID: "signed", Key: key, DPoP: dpop}, dpop
}

func TestAPrivateKeyJWTClientGetsATokenHeldToItsKey(t *testing.T) {
	held := newFake(t)
	client, dpop := signedClient(t, held)

	token, err := client.ClientCredentials(context.Background(), TokenRequest{Scope: []string{"files:read"}, Resource: []string{held.audience}})
	if err != nil {
		t.Fatal(err)
	}

	if !token.Bound() {
		t.Fatalf("expected a DPoP token, got %q", token.TokenType)
	}

	claims, err := NewVerifier(client.Issuer, held.audience).Verify(context.Background(), token.AccessToken)
	if err != nil {
		t.Fatal(err)
	}

	if !claims.Bound() || claims.Confirmation.Thumbprint != dpop.Thumbprint() {
		t.Fatalf("the token is held to %+v, the key is %s", claims.Confirmation, dpop.Thumbprint())
	}
}

func TestEachAssertionIsUsedOnce(t *testing.T) {
	held := newFake(t)
	client, _ := signedClient(t, held)

	for range 3 {
		if _, err := client.ClientCredentials(context.Background(), TokenRequest{}); err != nil {
			t.Fatal(err)
		}
	}
}

func TestATokenEndpointNonceIsAnsweredOnce(t *testing.T) {
	held := newFake(t)
	held.nonce = "fresh-nonce"
	client, _ := signedClient(t, held)

	if _, err := client.ClientCredentials(context.Background(), TokenRequest{}); err != nil {
		t.Fatal(err)
	}
}

func TestABearerAnswerToADPoPClientIsRefused(t *testing.T) {
	server := httptest.NewServer(nil)
	defer server.Close()

	server.Config.Handler = http.HandlerFunc(func(response http.ResponseWriter, request *http.Request) {
		switch request.URL.Path {
		case discoveryPath:
			writeJSON(response, http.StatusOK, map[string]string{"issuer": server.URL, "token_endpoint": server.URL + "/token"})
		default:
			writeJSON(response, http.StatusOK, map[string]any{"access_token": "plain", "token_type": "Bearer", "expires_in": 60})
		}
	})

	issuer, err := Discover(context.Background(), server.URL)
	if err != nil {
		t.Fatal(err)
	}

	dpop, _ := GenerateKey()
	client := &Client{Issuer: issuer, ID: "machine", Secret: "secret", DPoP: dpop}

	if _, err := client.ClientCredentials(context.Background(), TokenRequest{}); !HasCode(err, "invalid_dpop_proof") {
		t.Fatalf("expected the downgrade to be refused, got %v", err)
	}
}

func TestTheDeviceFlowWaitsForApproval(t *testing.T) {
	devicePause = 10 * time.Millisecond
	t.Cleanup(func() { devicePause = 5 * time.Second })

	held := newFake(t)
	held.pending = 3
	held.add("tv", &fakeClient{method: NoAuth, scope: "openid"})

	client := &Client{Issuer: discovered(t, held), ID: "tv"}

	device, err := client.DeviceAuthorization(context.Background(), TokenRequest{Scope: []string{"openid"}})
	if err != nil {
		t.Fatal(err)
	}

	if device.UserCode != "ABCD EFGH" {
		t.Fatalf("unexpected user code %q", device.UserCode)
	}

	token, err := client.AwaitDevice(context.Background(), device)
	if err != nil {
		t.Fatal(err)
	}

	if token.AccessToken == "" || held.pending != 0 {
		t.Fatalf("expected a token after every pending answer, got %+v with %d left", token, held.pending)
	}
}

func TestTheDeviceFlowStopsWithItsContext(t *testing.T) {
	devicePause = 10 * time.Millisecond
	t.Cleanup(func() { devicePause = 5 * time.Second })

	held := newFake(t)
	held.pending = 1000
	held.add("tv", &fakeClient{method: NoAuth})

	client := &Client{Issuer: discovered(t, held), ID: "tv"}

	device, err := client.DeviceAuthorization(context.Background(), TokenRequest{})
	if err != nil {
		t.Fatal(err)
	}

	ctx, cancel := context.WithTimeout(context.Background(), 100*time.Millisecond)
	defer cancel()

	if _, err := client.AwaitDevice(ctx, device); !errors.Is(err, context.DeadlineExceeded) {
		t.Fatalf("expected the deadline, got %v", err)
	}
}

func TestARefreshSourceKeepsEachRotatedToken(t *testing.T) {
	held := newFake(t)
	held.add("app", &fakeClient{secret: "secret", method: ClientSecretBasic})

	client := &Client{Issuer: discovered(t, held), ID: "app", Secret: "secret"}

	first, err := client.ClientCredentials(context.Background(), TokenRequest{})
	if err != nil {
		t.Fatal(err)
	}

	first.Expiry = time.Now().Add(-time.Minute)

	var kept []*Token
	source := client.RefreshSource(first, TokenRequest{}, func(token *Token) error {
		kept = append(kept, token)
		return nil
	})

	renewed, err := source.Token(context.Background())
	if err != nil {
		t.Fatal(err)
	}

	again, err := source.Token(context.Background())
	if err != nil {
		t.Fatal(err)
	}

	if renewed != again || len(kept) != 1 || renewed.RefreshToken == first.RefreshToken {
		t.Fatalf("expected one rotation that was kept, got %d", len(kept))
	}

	if _, err := client.Refresh(context.Background(), first.RefreshToken, TokenRequest{}); !HasCode(err, "invalid_grant") {
		t.Fatalf("expected the spent refresh token to be refused, got %v", err)
	}
}

func TestRevocationSendsTheToken(t *testing.T) {
	held := newFake(t)
	held.add("app", &fakeClient{secret: "secret", method: ClientSecretBasic})

	client := &Client{Issuer: discovered(t, held), ID: "app", Secret: "secret"}

	if err := client.Revoke(context.Background(), "a-token", "refresh_token"); err != nil {
		t.Fatal(err)
	}

	if len(held.revoked) != 1 || held.revoked[0] != "a-token" {
		t.Fatalf("revoked %v", held.revoked)
	}
}

func TestRegistrationWithAnInitialAccessToken(t *testing.T) {
	held := newFake(t)
	held.initial["one-time"] = "enrolled"

	issuer := discovered(t, held)
	key, _ := GenerateKey()

	registration, err := issuer.Register(context.Background(), ClientMetadata{
		Name:                    "A machine",
		GrantTypes:              []string{GrantClientCredentials},
		TokenEndpointAuthMethod: PrivateKeyJWT,
		JWKS:                    key.JWKS(),
		Scope:                   "files:read",
	}, "one-time")
	if err != nil {
		t.Fatal(err)
	}

	if _, err := issuer.Register(context.Background(), ClientMetadata{}, "one-time"); !HasCode(err, "invalid_token") {
		t.Fatalf("expected a spent initial access token to be refused, got %v", err)
	}

	read, err := issuer.ReadRegistration(context.Background(), registration)
	if err != nil {
		t.Fatal(err)
	}

	if read.RegistrationAccessToken != registration.RegistrationAccessToken || read.TokenEndpointAuthMethod != PrivateKeyJWT {
		t.Fatalf("the read lost what was held: %+v", read)
	}

	updated, err := issuer.UpdateRegistration(context.Background(), read, ClientMetadata{Scope: "files:read files:write"})
	if err != nil {
		t.Fatal(err)
	}

	token, err := issuer.Client(updated, key, nil).ClientCredentials(context.Background(), TokenRequest{})
	if err != nil {
		t.Fatal(err)
	}

	if token.Scope != "files:read files:write" {
		t.Fatalf("unexpected scope %q", token.Scope)
	}

	if err := issuer.DeleteRegistration(context.Background(), updated); err != nil {
		t.Fatal(err)
	}

	if _, err := issuer.ReadRegistration(context.Background(), updated); !HasCode(err, "invalid_token") {
		t.Fatalf("expected the deleted registration to be gone, got %v", err)
	}
}

func TestARegistrationURIOnAnotherOriginNeverSeesTheToken(t *testing.T) {
	held := newFake(t)
	held.initial["one-time"] = "enrolled"
	held.foreignURI = true

	if _, err := discovered(t, held).Register(context.Background(), ClientMetadata{}, "one-time"); !errors.Is(err, ErrForeign) {
		t.Fatalf("expected ErrForeign, got %v", err)
	}
}

func TestKeysSurviveJSON(t *testing.T) {
	key, err := GenerateKey()
	if err != nil {
		t.Fatal(err)
	}

	encoded, err := json.Marshal(key)
	if err != nil {
		t.Fatal(err)
	}

	if !strings.Contains(string(encoded), `"d":`) {
		t.Fatal("the private key was not written")
	}

	if strings.Contains(string(key.PublicJWK()), `"d":`) || strings.Contains(string(key.JWKS()), `"d":`) {
		t.Fatal("the public forms carry the private key")
	}

	var read Key
	if err := json.Unmarshal(encoded, &read); err != nil {
		t.Fatal(err)
	}

	if read.Thumbprint() != key.Thumbprint() {
		t.Fatal("the thumbprint changed")
	}

	if _, err := ParseKey(key.PublicJWK()); err == nil {
		t.Fatal("a public key was accepted as a private one")
	}
}

type resourceServer struct {
	*httptest.Server
	verifier *Verifier
	seen     []*Claims
}

func newResource(t *testing.T, issuer *Issuer, audience string) *resourceServer {
	t.Helper()

	held := &resourceServer{verifier: NewVerifier(issuer, audience)}
	held.Server = httptest.NewServer(held.verifier.Middleware(http.HandlerFunc(func(response http.ResponseWriter, request *http.Request) {
		claims, _ := ClaimsFrom(request.Context())
		held.seen = append(held.seen, claims)

		body, _ := io.ReadAll(request.Body)
		response.Write(body)
	})))
	t.Cleanup(held.Close)

	return held
}

func TestATransportSignsEachRequestForItsResource(t *testing.T) {
	held := newFake(t)
	client, _ := signedClient(t, held)
	resource := newResource(t, client.Issuer, held.audience)

	http := client.HTTPClient(client.CredentialsSource(TokenRequest{Resource: []string{held.audience}}), resource.URL)

	for _, body := range []string{"one", "two"} {
		response, err := http.Post(resource.URL+"/files?path=x", "text/plain", strings.NewReader(body))
		if err != nil {
			t.Fatal(err)
		}

		echoed, _ := io.ReadAll(response.Body)
		response.Body.Close()

		if response.StatusCode != 200 || string(echoed) != body {
			t.Fatalf("%d %s: %s", response.StatusCode, body, response.Header.Get("WWW-Authenticate"))
		}
	}

	if len(resource.seen) != 2 || resource.seen[0].Subject != "signed" {
		t.Fatalf("unexpected claims %+v", resource.seen)
	}
}

func TestATransportRefusesAnOriginItWasNotGiven(t *testing.T) {
	held := newFake(t)
	client, _ := signedClient(t, held)

	http := client.HTTPClient(client.CredentialsSource(TokenRequest{}), "https://files.example")

	if _, err := http.Get(held.url() + "/elsewhere"); !errors.Is(err, ErrForeign) {
		t.Fatalf("expected ErrForeign, got %v", err)
	}
}

func boundRequest(t *testing.T, client *Client, dpop *Key, method, target string) (*http.Request, *Token) {
	t.Helper()

	token, err := client.ClientCredentials(context.Background(), TokenRequest{})
	if err != nil {
		t.Fatal(err)
	}

	proof, err := dpop.Proof(method, target, token.AccessToken, "")
	if err != nil {
		t.Fatal(err)
	}

	request := httptest.NewRequest(method, target, nil)
	request.Header.Set("Authorization", "DPoP "+token.AccessToken)
	request.Header.Set("DPoP", proof)

	return request, token
}

func TestAVerifierRefusesMisusedProofs(t *testing.T) {
	held := newFake(t)
	client, dpop := signedClient(t, held)
	verifier := NewVerifier(client.Issuer, held.audience)
	target := "http://files.example/files"

	request, token := boundRequest(t, client, dpop, http.MethodGet, target)

	if _, err := verifier.Authenticate(request); err != nil {
		t.Fatalf("a good proof was refused: %v", err)
	}

	if _, err := verifier.Authenticate(request); err == nil || !strings.Contains(err.Error(), "already been used") {
		t.Fatalf("a replayed proof was accepted: %v", err)
	}

	cases := map[string]func(*http.Request){
		"Bearer": func(request *http.Request) {
			request.Header.Set("Authorization", "Bearer "+token.AccessToken)
		},
		"no proof": func(request *http.Request) {
			request.Header.Del("DPoP")
		},
		"another method": func(request *http.Request) {
			request.Method = http.MethodDelete
		},
		"another URL": func(request *http.Request) {
			request.URL.Path = "/other"
		},
		"another key": func(request *http.Request) {
			other, _ := GenerateKey()
			proof, _ := other.Proof(http.MethodGet, target, token.AccessToken, "")
			request.Header.Set("DPoP", proof)
		},
		"another token": func(request *http.Request) {
			proof, _ := dpop.Proof(http.MethodGet, target, "something else", "")
			request.Header.Set("DPoP", proof)
		},
	}

	for name, change := range cases {
		t.Run(name, func(t *testing.T) {
			request, _ := boundRequest(t, client, dpop, http.MethodGet, target)
			change(request)

			if _, err := verifier.Authenticate(request); !errors.Is(err, ErrInvalidToken) {
				t.Fatalf("expected ErrInvalidToken, got %v", err)
			}
		})
	}
}

func TestAVerifierChecksTheTokenItself(t *testing.T) {
	held := newFake(t)
	issuer := discovered(t, held)
	verifier := NewVerifier(issuer, held.audience)

	good := map[string]any{
		"iss": held.url(), "sub": "ada", "aud": held.audience, "jti": "1",
		"exp": time.Now().Add(time.Hour).Unix(), "iat": time.Now().Unix(),
	}

	if _, err := verifier.Verify(context.Background(), held.issue(good, accessTokenType)); err != nil {
		t.Fatalf("a good token was refused: %v", err)
	}

	changed := func(name string, value any) map[string]any {
		held := map[string]any{}
		for key, value := range good {
			held[key] = value
		}

		if value == nil {
			delete(held, name)
		} else {
			held[name] = value
		}

		return held
	}

	cases := map[string]string{
		"another audience": held.issue(changed("aud", "https://other.example"), accessTokenType),
		"another issuer":   held.issue(changed("iss", "https://other.example"), accessTokenType),
		"expired":          held.issue(changed("exp", time.Now().Add(-time.Hour).Unix()), accessTokenType),
		"no jti":           held.issue(changed("jti", nil), accessTokenType),
		"an ID token":      held.issue(good, "JWT"),
		"not a JWT":        "nonsense",
	}

	for name, token := range cases {
		t.Run(name, func(t *testing.T) {
			if _, err := verifier.Verify(context.Background(), token); err == nil {
				t.Fatal("it was accepted")
			}
		})
	}

	forged, _ := GenerateKey()
	signed, _ := forged.sign(accessTokenType, good, false)

	if _, err := verifier.Verify(context.Background(), signed); err == nil {
		t.Fatal("a token signed by another key was accepted")
	}
}

func TestTheMiddlewareChallengesWithoutAToken(t *testing.T) {
	held := newFake(t)
	resource := newResource(t, discovered(t, held), held.audience)

	response, err := http.Get(resource.URL)
	if err != nil {
		t.Fatal(err)
	}
	response.Body.Close()

	if response.StatusCode != http.StatusUnauthorized || len(response.Header.Values("WWW-Authenticate")) != 2 {
		t.Fatalf("%d %v", response.StatusCode, response.Header.Values("WWW-Authenticate"))
	}
}

func TestResourceDiscoveryFindsTheIssuer(t *testing.T) {
	server := httptest.NewServer(nil)
	defer server.Close()

	server.Config.Handler = http.HandlerFunc(func(response http.ResponseWriter, request *http.Request) {
		if request.URL.Path != resourcePath {
			http.NotFound(response, request)
			return
		}

		writeJSON(response, http.StatusOK, ResourceMetadata{Resource: server.URL, AuthorizationServers: []string{"https://id.example"}})
	})

	found, err := DiscoverResource(context.Background(), server.URL)
	if err != nil {
		t.Fatal(err)
	}

	if found.AuthorizationServers[0] != "https://id.example" {
		t.Fatalf("unexpected %+v", found)
	}
}
