package masks

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"maps"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync/atomic"
	"testing"
	"time"

	"github.com/go-jose/go-jose/v4/jwt"
)

func discovered(t *testing.T, held *fake) *Issuer {
	t.Helper()

	issuer, err := Discover(context.Background(), held.url(), quick)
	if err != nil {
		t.Fatal(err)
	}

	return issuer
}

func quick(held *settings) {
	held.pause = 10 * time.Millisecond
}

func secretClient(t *testing.T, held *fake, scope string) *Client {
	t.Helper()

	held.add("app", &fakeClient{secret: "secret", method: ClientSecretBasic, scope: scope})

	return &Client{Issuer: discovered(t, held), ID: "app", Secret: "secret"}
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

	if err := held.check("http://10.0.0.4"); !is[*Insecure](err) {
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

	var refused *Refused
	if !errors.As(err, &refused) || refused.Code != "invalid_client" || refused.Status != http.StatusUnauthorized {
		t.Fatalf("expected invalid_client, got %v", err)
	}
}

func signedClient(t *testing.T, held *fake) *Client {
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

	return &Client{Issuer: discovered(t, held), ID: "signed", Key: key, DPoP: dpop}
}

func TestAPrivateKeyJWTClientGetsATokenHeldToItsKey(t *testing.T) {
	held := newFake(t)
	client := signedClient(t, held)
	dpop := client.DPoP

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
	client := signedClient(t, held)

	for range 3 {
		if _, err := client.ClientCredentials(context.Background(), TokenRequest{}); err != nil {
			t.Fatal(err)
		}
	}
}

func TestATokenEndpointNonceIsAnsweredOnce(t *testing.T) {
	held := newFake(t)
	held.nonce = "fresh-nonce"
	client := signedClient(t, held)

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
	client := secretClient(t, held, "")

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
	client := secretClient(t, held, "")

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

	if _, err := discovered(t, held).Register(context.Background(), ClientMetadata{}, "one-time"); !is[*Foreign](err) {
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
	client := signedClient(t, held)
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
	client := signedClient(t, held)

	http := client.HTTPClient(client.CredentialsSource(TokenRequest{}), "https://files.example")

	if _, err := http.Get(held.url() + "/elsewhere"); !is[*Foreign](err) {
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
	client := signedClient(t, held)
	dpop := client.DPoP
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

			if _, err := verifier.Authenticate(request); !is[*InvalidToken](err) {
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
		held := maps.Clone(good)

		if value == nil {
			delete(held, name)
		} else {
			held[name] = value
		}

		return held
	}

	cases := map[string][2]string{
		"another audience": {held.issue(changed("aud", "https://other.example"), accessTokenType), "that token was issued for another app"},
		"another issuer":   {held.issue(changed("iss", "https://other.example"), accessTokenType), "that token was issued by another server"},
		"expired":          {held.issue(changed("exp", time.Now().Add(-time.Hour).Unix()), accessTokenType), "that token has expired"},
		"no jti":           {held.issue(changed("jti", nil), accessTokenType), "that token is missing jti and exp"},
		"an ID token":      {held.issue(good, "JWT"), "that token is typed JWT, not at+jwt"},
		"not a JWT":        {"nonsense", "that token is not a signed JWT"},
	}

	for name, refused := range cases {
		t.Run(name, func(t *testing.T) {
			_, err := verifier.Verify(context.Background(), refused[0])

			var bad *InvalidToken
			if !errors.As(err, &bad) || bad.Description != refused[1] {
				t.Fatalf("it was refused with %v", err)
			}
		})
	}

	if _, err := verifier.Verify(context.Background(), newFake(t).issue(good, accessTokenType)); err == nil {
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

	challenges := response.Header.Values("WWW-Authenticate")

	if response.StatusCode != http.StatusUnauthorized || len(challenges) != 2 || challenges[0] != "Bearer" ||
		strings.Contains(challenges[1], "error") {
		t.Fatalf("%d %q", response.StatusCode, challenges)
	}
}

func TestTheMiddlewareNamesTheErrorForATokenItRefuses(t *testing.T) {
	held := newFake(t)
	resource := newResource(t, discovered(t, held), held.audience)

	request, _ := http.NewRequest(http.MethodGet, resource.URL, nil)
	request.Header.Set("Authorization", "Bearer nonsense")

	response, err := http.DefaultClient.Do(request)
	if err != nil {
		t.Fatal(err)
	}
	response.Body.Close()

	if challenge := response.Header.Get("WWW-Authenticate"); challenge != `Bearer error="invalid_token", error_description="that token is not a signed JWT"` {
		t.Fatalf("%d %q", response.StatusCode, challenge)
	}
}

func TestResourceDiscoveryFindsTheIssuer(t *testing.T) {
	server := httptest.NewServer(nil)
	defer server.Close()

	server.Config.Handler = http.HandlerFunc(func(response http.ResponseWriter, request *http.Request) {
		if request.URL.Path != ResourceMetadataPath {
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

func TestATransportSendsABearerTokenWhenTheTokenIsNotHeld(t *testing.T) {
	held := newFake(t)
	client := secretClient(t, held, "files:read files:write")
	resource := newResource(t, client.Issuer, held.audience)

	response, err := client.HTTPClient(client.CredentialsSource(TokenRequest{}), resource.URL).Get(resource.URL)
	if err != nil {
		t.Fatal(err)
	}
	response.Body.Close()

	if response.StatusCode != http.StatusOK || !resource.seen[0].HasScope("files:write") || resource.seen[0].Bound() {
		t.Fatalf("%d %+v", response.StatusCode, resource.seen)
	}
}

func TestATransportAnswersAResourceNonceAndReplaysTheBody(t *testing.T) {
	held := newFake(t)
	client := signedClient(t, held)

	var nonces []string
	var bodies []string

	server := httptest.NewServer(http.HandlerFunc(func(response http.ResponseWriter, request *http.Request) {
		claims := proofClaims{}
		if parsed, err := jwt.ParseSigned(request.Header.Get("DPoP"), proofAlgorithms); err == nil {
			_ = parsed.UnsafeClaimsWithoutVerification(&claims)
		}
		nonces = append(nonces, claims.Nonce)

		body, _ := io.ReadAll(request.Body)
		bodies = append(bodies, string(body))

		if claims.Nonce != "server-nonce" {
			response.Header().Set("DPoP-Nonce", "server-nonce")
			response.Header().Set("WWW-Authenticate", `DPoP error="use_dpop_nonce"`)
			response.WriteHeader(http.StatusUnauthorized)

			return
		}

		response.WriteHeader(http.StatusOK)
	}))
	defer server.Close()

	http := client.HTTPClient(client.CredentialsSource(TokenRequest{}), server.URL)

	response, err := http.Post(server.URL, "text/plain", strings.NewReader("payload"))
	if err != nil {
		t.Fatal(err)
	}
	response.Body.Close()

	if response.StatusCode != 200 || len(nonces) != 2 || nonces[0] != "" || bodies[1] != "payload" {
		t.Fatalf("%d %q %q", response.StatusCode, nonces, bodies)
	}

	response, err = http.Post(server.URL, "text/plain", strings.NewReader("later"))
	if err != nil {
		t.Fatal(err)
	}
	response.Body.Close()

	if len(nonces) != 3 || nonces[2] != "server-nonce" {
		t.Fatalf("the nonce was not remembered: %q", nonces)
	}
}

func TestAnAppEnrollsAMachineAndUnenrollsIt(t *testing.T) {
	held := newFake(t)
	app := secretClient(t, held, "")

	enrollment, err := app.Enroll(context.Background(), EnrollmentRequest{Scope: []string{"xixo:agent"}, Name: "nas", Lifetime: 15 * time.Minute})
	if err != nil {
		t.Fatal(err)
	}

	sent := held.seen["/enrollments"]
	if sent.Get("scope") != "xixo:agent" || sent.Get("client_name") != "nas" || sent.Get("expires_in") != "900" {
		t.Fatalf("unexpected form %v", sent)
	}

	if enrollment.InitialAccessToken == "" || enrollment.Scopes()[0] != "xixo:agent" || time.Until(enrollment.Expiry) < 14*time.Minute {
		t.Fatalf("unexpected enrollment %+v", enrollment)
	}

	key, _ := GenerateKey()
	dpop, _ := GenerateKey()

	registration, err := app.Issuer.Register(context.Background(), ClientMetadata{
		Name:                    "nas",
		TokenEndpointAuthMethod: PrivateKeyJWT,
		JWKS:                    key.JWKS(),
	}, enrollment.InitialAccessToken)
	if err != nil {
		t.Fatal(err)
	}

	machine := app.Issuer.Client(registration, key, dpop)
	token, err := machine.ClientCredentials(context.Background(), TokenRequest{})
	if err != nil {
		t.Fatal(err)
	}

	if err := app.Unenroll(context.Background(), registration.ClientID); err != nil {
		t.Fatal(err)
	}

	if _, err := machine.ClientCredentials(context.Background(), TokenRequest{}); !HasCode(err, "invalid_client") {
		t.Fatalf("expected the unenrolled machine to be refused, got %v", err)
	}

	introspected, err := app.Introspect(context.Background(), token.AccessToken, "access_token")
	if err != nil || introspected.Active {
		t.Fatalf("expected the machine's token to be gone, got %+v %v", introspected, err)
	}
}

func TestAnAppUnenrollsOnlyItsOwnMachines(t *testing.T) {
	held := newFake(t)
	app := signedClient(t, held)
	held.add("other", &fakeClient{secret: "secret", method: ClientSecretPost})
	held.enrolledBy["theirs"] = "other"

	err := app.Unenroll(context.Background(), "theirs")

	var refused *Refused
	if !errors.As(err, &refused) || refused.Status != http.StatusNotFound {
		t.Fatalf("expected a 404, got %v", err)
	}

	enrollment, err := app.Enroll(context.Background(), EnrollmentRequest{Scope: []string{"xixo:agent"}})
	if err != nil {
		t.Fatal(err)
	}

	held.lock.Lock()
	var mine string
	for machine, by := range held.enrolledBy {
		if by == "signed" {
			mine = machine
		}
	}
	held.lock.Unlock()

	if enrollment.InitialAccessToken == "" || held.seen["/enrollments"].Has("expires_in") || held.seen["/enrollments"].Has("client_name") {
		t.Fatalf("unexpected enrollment %+v %v", enrollment, held.seen["/enrollments"])
	}

	if err := app.Unenroll(context.Background(), mine); err != nil {
		t.Fatalf("a signed app could not unenroll its machine: %v", err)
	}

	for _, refused := range []string{"", ".", ".."} {
		if err := app.Unenroll(context.Background(), refused); err == nil {
			t.Errorf("%q was sent", refused)
		}
	}
}

func TestAnEnrollmentWithoutAScopeIsRefused(t *testing.T) {
	held := newFake(t)
	app := secretClient(t, held, "")

	if _, err := app.Enroll(context.Background(), EnrollmentRequest{}); !HasCode(err, "invalid_request") {
		t.Fatalf("expected invalid_request, got %v", err)
	}
}

func TestIntrospectionDescribesALiveToken(t *testing.T) {
	held := newFake(t)
	client := signedClient(t, held)

	token, err := client.ClientCredentials(context.Background(), TokenRequest{Scope: []string{"files:read"}})
	if err != nil {
		t.Fatal(err)
	}

	introspected, err := client.Introspect(context.Background(), token.AccessToken, "access_token")
	if err != nil {
		t.Fatal(err)
	}

	if held.seen["/introspect"].Get("token_type_hint") != "access_token" {
		t.Fatalf("the hint was not sent: %v", held.seen["/introspect"])
	}

	if !introspected.Active || !introspected.HasScope("files:read") || introspected.HasScope("files:write") || introspected.ClientID != "signed" {
		t.Fatalf("unexpected %+v", introspected)
	}

	if !introspected.Bound() || introspected.Confirmation.Thumbprint != client.DPoP.Thumbprint() || introspected.TokenType != DPoP {
		t.Fatalf("expected the token to be held to the client's key, got %+v", introspected.Confirmation)
	}

	if !introspected.Organization.HasRole("owner", "admin") || introspected.Audience[0] != held.audience {
		t.Fatalf("unexpected organization or audience %+v", introspected)
	}
}

func TestIntrospectionCallsAnUnknownOrStaleTokenInactive(t *testing.T) {
	held := newFake(t)
	client := secretClient(t, held, "files:read")

	unknown, err := client.Introspect(context.Background(), "nonsense", "")
	if err != nil {
		t.Fatal(err)
	}

	if unknown.Active || unknown.Scope != "" || unknown.HasScope("leaked") {
		t.Fatalf("an inactive answer kept %+v", unknown)
	}

	token, err := client.ClientCredentials(context.Background(), TokenRequest{})
	if err != nil {
		t.Fatal(err)
	}

	held.staleActive = true

	stale, err := client.Introspect(context.Background(), token.AccessToken, "")
	if err != nil {
		t.Fatal(err)
	}

	if stale.Active || stale.HasScope("files:read") {
		t.Fatalf("an expired token was called active: %+v", stale)
	}
}

func TestATokenExchangeKeepsTheKey(t *testing.T) {
	held := newFake(t)
	held.nonce = "fresh-nonce"
	client := signedClient(t, held)

	subject, err := client.ClientCredentials(context.Background(), TokenRequest{Scope: []string{"files:read files:write"}})
	if err != nil {
		t.Fatal(err)
	}

	exchanged, err := client.Exchange(context.Background(), ExchangeRequest{
		SubjectToken: subject.AccessToken,
		ActorToken:   "actor",
		Audience:     []string{"files"},
		Scope:        []string{"files:read"},
		Resource:     []string{held.audience},
		Lifetime:     5 * time.Minute,
	})
	if err != nil {
		t.Fatal(err)
	}

	sent := held.seen["/token"]
	want := map[string]string{
		"grant_type":         GrantTokenExchange,
		"subject_token_type": TokenTypeAccessToken,
		"actor_token":        "actor",
		"actor_token_type":   TokenTypeAccessToken,
		"audience":           "files",
		"scope":              "files:read",
		"resource":           held.audience,
		"requested_lifetime": "300",
	}

	for name, value := range want {
		if sent.Get(name) != value {
			t.Errorf("%s was %q, expected %q", name, sent.Get(name), value)
		}
	}

	if sent.Has("requested_token_type") {
		t.Errorf("requested_token_type was sent unasked")
	}

	if !exchanged.Bound() || exchanged.IssuedTokenType != TokenTypeAccessToken || exchanged.Scope != "files:read" {
		t.Fatalf("unexpected %+v", exchanged)
	}

	claims, err := NewVerifier(client.Issuer, held.audience).Verify(context.Background(), exchanged.AccessToken)
	if err != nil || claims.Confirmation.Thumbprint != client.DPoP.Thumbprint() {
		t.Fatalf("the exchanged token is not held to the client's key: %v", err)
	}

	stranger, _ := GenerateKey()
	thief := *client
	thief.DPoP = stranger

	if _, err := thief.Exchange(context.Background(), ExchangeRequest{SubjectToken: subject.AccessToken}); !HasCode(err, "invalid_dpop_proof") {
		t.Fatalf("a bound subject token was exchanged with another key: %v", err)
	}
}

func TestATokenExchangeForAnUpstreamTokenIsBearer(t *testing.T) {
	held := newFake(t)
	client := signedClient(t, held)

	subject, err := client.ClientCredentials(context.Background(), TokenRequest{})
	if err != nil {
		t.Fatal(err)
	}

	upstream, err := client.Exchange(context.Background(), ExchangeRequest{
		SubjectToken:       subject.AccessToken,
		RequestedTokenType: TokenTypeUpstreamAccessToken,
		Audience:           []string{"connection-uuid"},
	})
	if err != nil {
		t.Fatal(err)
	}

	if upstream.Bound() || upstream.IssuedTokenType != TokenTypeUpstreamAccessToken || !strings.HasPrefix(upstream.AccessToken, "upstream-") {
		t.Fatalf("unexpected %+v", upstream)
	}
}

func TestATokenExchangeRefusesAnotherIssuedType(t *testing.T) {
	held := newFake(t)
	held.issuedAs = TokenTypeIDToken
	client := secretClient(t, held, "")

	subject, err := client.ClientCredentials(context.Background(), TokenRequest{})
	if err != nil {
		t.Fatal(err)
	}

	if _, err := client.Exchange(context.Background(), ExchangeRequest{SubjectToken: subject.AccessToken}); !HasCode(err, "server_error") {
		t.Fatalf("expected the wrong type to be refused, got %v", err)
	}

	if _, err := client.Exchange(context.Background(), ExchangeRequest{}); err == nil {
		t.Fatal("an exchange without a subject token was sent")
	}
}

func TestVerifiersSharingAReplayStoreRefuseAProofSeenByEither(t *testing.T) {
	held := newFake(t)
	client := signedClient(t, held)
	target := "http://files.example/files"

	var asked []string
	shared := &MemoryReplayStore{}
	store := ReplayStoreFunc(func(ctx context.Context, key string, expiresIn time.Duration) (bool, error) {
		asked = append(asked, key)

		if expiresIn < proofWindow {
			t.Errorf("a proof is remembered for only %s", expiresIn)
		}

		return shared.First(ctx, key, expiresIn)
	})

	one := NewVerifier(client.Issuer, held.audience)
	one.Replay = store
	two := NewVerifier(client.Issuer, held.audience)
	two.Replay = store

	request, _ := boundRequest(t, client, client.DPoP, http.MethodGet, target)

	if _, err := one.Authenticate(request); err != nil {
		t.Fatal(err)
	}

	if _, err := two.Authenticate(request); !is[*InvalidToken](err) {
		t.Fatalf("the other verifier accepted a replayed proof: %v", err)
	}

	if len(asked) != 2 || !strings.HasPrefix(asked[0], client.DPoP.Thumbprint()+":") {
		t.Fatalf("unexpected keys %q", asked)
	}
}

func TestAReplayStoreThatFailsRefusesTheRequest(t *testing.T) {
	held := newFake(t)
	client := signedClient(t, held)
	resource := newResource(t, client.Issuer, held.audience)
	resource.verifier.Replay = ReplayStoreFunc(func(context.Context, string, time.Duration) (bool, error) {
		return true, errors.New("redis is down")
	})

	request, _ := boundRequest(t, client, client.DPoP, http.MethodGet, "http://files.example/files")

	if _, err := resource.verifier.Authenticate(request); !is[*Unavailable](err) || is[*InvalidToken](err) {
		t.Fatalf("expected ErrReplayStore, got %v", err)
	}

	api := client.HTTPClient(client.CredentialsSource(TokenRequest{}), resource.URL)

	response, err := api.Get(resource.URL)
	if err != nil {
		t.Fatal(err)
	}
	response.Body.Close()

	if response.StatusCode != http.StatusServiceUnavailable || len(resource.seen) != 0 {
		t.Fatalf("expected 503 before the handler, got %d with %d handled", response.StatusCode, len(resource.seen))
	}
}

func TestTheMemoryReplayStoreForgetsAKeyAfterItExpires(t *testing.T) {
	store := &MemoryReplayStore{}

	for _, want := range []bool{true, false} {
		if first, err := store.First(context.Background(), "k", 20*time.Millisecond); err != nil || first != want {
			t.Fatalf("expected %v, got %v %v", want, first, err)
		}
	}

	time.Sleep(30 * time.Millisecond)

	if first, _ := store.First(context.Background(), "k", time.Minute); !first {
		t.Fatal("an expired key was still remembered")
	}
}

func TestAChallengePointsAtTheResourceMetadata(t *testing.T) {
	found, err := ResourceMetadataURL("https://files.example:443/api/")
	if err != nil || found != "https://files.example/.well-known/oauth-protected-resource/api" {
		t.Fatalf("unexpected %q %v", found, err)
	}

	verifier := &Verifier{ResourceMetadata: found}
	held := verifier.Challenge("insufficient_scope", `needs "files:write"`, "files:write")

	if len(held) != 2 || !strings.HasPrefix(held[0], `Bearer error="insufficient_scope", error_description="needs  files:write ", scope="files:write", resource_metadata="`+found+`"`) ||
		!strings.HasPrefix(held[1], `DPoP algs="ES256 `) {
		t.Fatalf("unexpected %q", held)
	}

	if _, err := ResourceMetadataURL("files"); err == nil {
		t.Fatal("a relative resource was accepted")
	}
}

func TestACredentialIsNeverFollowedToAnotherAddress(t *testing.T) {
	var reached atomic.Int32

	elsewhere := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		reached.Add(1)
		w.WriteHeader(http.StatusOK)
	}))
	t.Cleanup(elsewhere.Close)

	var issuer *httptest.Server
	issuer = httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/.well-known/openid-configuration" {
			w.Header().Set("Content-Type", "application/json")
			_, _ = w.Write([]byte(`{"issuer":"` + issuer.URL + `","token_endpoint":"` + issuer.URL + `/token","revocation_endpoint":"` + issuer.URL + `/revoke"}`))

			return
		}

		http.Redirect(w, r, elsewhere.URL+r.URL.Path, http.StatusTemporaryRedirect)
	}))
	t.Cleanup(issuer.Close)

	found, err := Discover(context.Background(), issuer.URL)
	if err != nil {
		t.Fatal(err)
	}

	for _, method := range []AuthMethod{ClientSecretPost, ClientSecretBasic} {
		client := &Client{Issuer: found, ID: "app", Secret: "secret", Method: method}

		if _, err := client.Refresh(context.Background(), "refresh-token", TokenRequest{}); err == nil {
			t.Fatalf("a redirected token request succeeded with %s", method)
		}

		if err := client.Revoke(context.Background(), "refresh-token", GrantRefreshToken); err == nil {
			t.Fatalf("a redirected revocation succeeded with %s", method)
		}
	}

	if reached.Load() != 0 {
		t.Fatalf("a client secret or refresh token was sent on to another address %d times", reached.Load())
	}
}

func TestAReusedTokenWithNothingToRenewItIsAnError(t *testing.T) {
	source := ReuseTokenSource(&Token{AccessToken: "spent", Expiry: time.Now().Add(-time.Minute)}, nil)

	if _, err := source.Token(context.Background()); err == nil {
		t.Fatal("an expired token with nothing to renew it was handed out")
	}
}
