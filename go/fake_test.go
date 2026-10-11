package masks

import (
	"crypto"
	"crypto/rand"
	"crypto/rsa"
	"encoding/base64"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"net/url"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/go-jose/go-jose/v4"
	"github.com/go-jose/go-jose/v4/jwt"
)

type fakeClient struct {
	secret  string
	method  AuthMethod
	jwks    jose.JSONWebKeySet
	scope   string
	refresh map[string]bool
}

type fake struct {
	t        *testing.T
	server   *httptest.Server
	signing  *rsa.PrivateKey
	kid      string
	audience string

	lock          sync.Mutex
	clients       map[string]*fakeClient
	registrations map[string]string
	initial       map[string]string
	pending       int
	slowed        bool
	revoked       []string
	assertions    map[string]bool
	nonce         string
	foreignURI    bool
}

func newFake(t *testing.T) *fake {
	t.Helper()

	signing, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		t.Fatal(err)
	}

	held := &fake{
		t:             t,
		signing:       signing,
		kid:           "signing-1",
		audience:      "https://files.example",
		clients:       map[string]*fakeClient{},
		registrations: map[string]string{},
		initial:       map[string]string{},
		assertions:    map[string]bool{},
	}

	mux := http.NewServeMux()
	mux.HandleFunc("GET /.well-known/openid-configuration", held.discovery)
	mux.HandleFunc("GET /.well-known/jwks.json", held.keys)
	mux.HandleFunc("POST /token", held.token)
	mux.HandleFunc("POST /device_authorization", held.device)
	mux.HandleFunc("POST /revoke", held.revoke)
	mux.HandleFunc("POST /register", held.register)
	mux.HandleFunc("GET /register/{id}", held.registration)
	mux.HandleFunc("PUT /register/{id}", held.registration)
	mux.HandleFunc("DELETE /register/{id}", held.registration)

	held.server = httptest.NewServer(mux)
	t.Cleanup(held.server.Close)

	return held
}

func (f *fake) url() string {
	return f.server.URL
}

func (f *fake) add(id string, client *fakeClient) {
	f.lock.Lock()
	defer f.lock.Unlock()

	if client.refresh == nil {
		client.refresh = map[string]bool{}
	}

	f.clients[id] = client
}

func (f *fake) discovery(response http.ResponseWriter, _ *http.Request) {
	base := f.url()

	writeJSON(response, http.StatusOK, map[string]any{
		"issuer":                        base,
		"token_endpoint":                base + "/token",
		"jwks_uri":                      base + "/.well-known/jwks.json",
		"device_authorization_endpoint": base + "/device_authorization",
		"revocation_endpoint":           base + "/revoke",
		"registration_endpoint":         base + "/register",
	})
}

func (f *fake) keys(response http.ResponseWriter, _ *http.Request) {
	writeJSON(response, http.StatusOK, jose.JSONWebKeySet{Keys: []jose.JSONWebKey{
		{Key: &f.signing.PublicKey, KeyID: f.kid, Algorithm: string(jose.RS256), Use: "sig"},
	}})
}

func (f *fake) issue(claims map[string]any, typ string) string {
	signer, err := jose.NewSigner(
		jose.SigningKey{Algorithm: jose.RS256, Key: jose.JSONWebKey{Key: f.signing, KeyID: f.kid}},
		(&jose.SignerOptions{}).WithType(jose.ContentType(typ)),
	)
	if err != nil {
		f.t.Fatal(err)
	}

	held, err := jwt.Signed(signer).Claims(claims).Serialize()
	if err != nil {
		f.t.Fatal(err)
	}

	return held
}

func (f *fake) accessToken(id, scope, jkt string) string {
	claims := map[string]any{
		"iss":       f.url(),
		"sub":       id,
		"aud":       f.audience,
		"exp":       time.Now().Add(time.Hour).Unix(),
		"iat":       time.Now().Unix(),
		"jti":       random(),
		"client_id": id,
		"scope":     scope,
	}

	if jkt != "" {
		claims["cnf"] = map[string]string{"jkt": jkt}
	}

	return f.issue(claims, accessTokenType)
}

func (f *fake) authenticated(request *http.Request) (string, *fakeClient, bool) {
	f.lock.Lock()
	defer f.lock.Unlock()

	if id, secret, ok := request.BasicAuth(); ok {
		id, _ = url.QueryUnescape(id)
		secret, _ = url.QueryUnescape(secret)
		client := f.clients[id]

		return id, client, client != nil && client.method == ClientSecretBasic && client.secret == secret
	}

	id := request.PostForm.Get("client_id")
	client := f.clients[id]

	if client == nil {
		return id, nil, false
	}

	switch client.method {
	case ClientSecretPost:
		return id, client, request.PostForm.Get("client_secret") == client.secret
	case NoAuth:
		return id, client, true
	case PrivateKeyJWT:
		return id, client, f.asserted(request, id, client)
	}

	return id, client, false
}

func (f *fake) asserted(request *http.Request, id string, client *fakeClient) bool {
	if request.PostForm.Get("client_assertion_type") != assertionType {
		return false
	}

	parsed, err := jwt.ParseSigned(request.PostForm.Get("client_assertion"), []jose.SignatureAlgorithm{jose.ES256})
	if err != nil {
		return false
	}

	keys := client.jwks.Key(parsed.Headers[0].KeyID)
	if len(keys) != 1 {
		return false
	}

	claims := jwt.Claims{}

	if parsed.Claims(keys[0].Key, &claims) != nil || claims.Issuer != id || claims.Subject != id || claims.ID == "" {
		return false
	}

	if claims.ValidateWithLeeway(jwt.Expected{AnyAudience: jwt.Audience{f.url(), f.url() + "/token"}, Time: time.Now()}, 0) != nil {
		return false
	}

	if f.assertions[claims.ID] {
		return false
	}

	f.assertions[claims.ID] = true

	return true
}

func (f *fake) proof(request *http.Request) (string, bool) {
	presented := request.Header.Get(DPoP)
	if presented == "" {
		return "", true
	}

	parsed, err := jwt.ParseSigned(presented, proofAlgorithms)
	if err != nil || !typed(parsed.Headers[0], proofType) || parsed.Headers[0].JSONWebKey == nil || !parsed.Headers[0].JSONWebKey.IsPublic() {
		return "", false
	}

	claims := proofClaims{}
	if parsed.Claims(parsed.Headers[0].JSONWebKey.Key, &claims) != nil {
		return "", false
	}

	if claims.Method != http.MethodPost || claims.Target != f.url()+request.URL.Path || claims.Hash != "" {
		return "", false
	}

	if f.nonce != "" && claims.Nonce != f.nonce {
		return "", false
	}

	held, err := parsed.Headers[0].JSONWebKey.Thumbprint(crypto.SHA256)
	if err != nil {
		return "", false
	}

	return base64.RawURLEncoding.EncodeToString(held), true
}

func (f *fake) token(response http.ResponseWriter, request *http.Request) {
	if err := request.ParseForm(); err != nil {
		oauthError(response, http.StatusBadRequest, "invalid_request")
		return
	}

	jkt, ok := f.proof(request)
	if !ok {
		if f.nonce != "" {
			response.Header().Set("DPoP-Nonce", f.nonce)
			oauthError(response, http.StatusBadRequest, "use_dpop_nonce")

			return
		}

		oauthError(response, http.StatusBadRequest, "invalid_dpop_proof")

		return
	}

	id, client, ok := f.authenticated(request)
	if !ok {
		oauthError(response, http.StatusUnauthorized, "invalid_client")
		return
	}

	f.lock.Lock()
	defer f.lock.Unlock()

	switch request.PostForm.Get("grant_type") {
	case GrantClientCredentials:
	case GrantRefreshToken:
		presented := request.PostForm.Get("refresh_token")
		if !client.refresh[presented] {
			oauthError(response, http.StatusBadRequest, "invalid_grant")
			return
		}

		delete(client.refresh, presented)
	case GrantDeviceCode:
		if f.pending > 0 {
			f.pending--

			if !f.slowed {
				f.slowed = true
				oauthError(response, http.StatusBadRequest, "slow_down")

				return
			}

			oauthError(response, http.StatusBadRequest, "authorization_pending")

			return
		}
	default:
		oauthError(response, http.StatusBadRequest, "unsupported_grant_type")
		return
	}

	scope := request.PostForm.Get("scope")
	if scope == "" {
		scope = client.scope
	}

	refresh := random()
	client.refresh[refresh] = true

	body := map[string]any{
		"access_token":  f.accessToken(id, scope, jkt),
		"token_type":    "Bearer",
		"expires_in":    3600,
		"scope":         scope,
		"refresh_token": refresh,
	}

	if jkt != "" {
		body["token_type"] = DPoP
	}

	writeJSON(response, http.StatusOK, body)
}

func (f *fake) device(response http.ResponseWriter, request *http.Request) {
	if err := request.ParseForm(); err != nil {
		oauthError(response, http.StatusBadRequest, "invalid_request")
		return
	}

	id, _, ok := f.authenticated(request)
	if !ok || request.PostForm.Get("client_id") != id {
		oauthError(response, http.StatusUnauthorized, "invalid_client")
		return
	}

	writeJSON(response, http.StatusOK, map[string]any{
		"device_code":      "device-code",
		"user_code":        "ABCD EFGH",
		"verification_uri": f.url() + "/device",
		"expires_in":       600,
		"interval":         0,
	})
}

func (f *fake) revoke(response http.ResponseWriter, request *http.Request) {
	if err := request.ParseForm(); err != nil {
		oauthError(response, http.StatusBadRequest, "invalid_request")
		return
	}

	if _, _, ok := f.authenticated(request); !ok {
		oauthError(response, http.StatusUnauthorized, "invalid_client")
		return
	}

	f.lock.Lock()
	f.revoked = append(f.revoked, request.PostForm.Get("token"))
	f.lock.Unlock()

	response.WriteHeader(http.StatusOK)
}

func (f *fake) register(response http.ResponseWriter, request *http.Request) {
	presented := strings.TrimPrefix(request.Header.Get("Authorization"), "Bearer ")

	f.lock.Lock()
	id, known := f.initial[presented]
	if known {
		delete(f.initial, presented)
	}
	f.lock.Unlock()

	if !known {
		oauthError(response, http.StatusUnauthorized, "invalid_token")
		return
	}

	metadata := ClientMetadata{}
	if err := json.NewDecoder(request.Body).Decode(&metadata); err != nil {
		oauthError(response, http.StatusBadRequest, "invalid_client_metadata")
		return
	}

	jwks := jose.JSONWebKeySet{}
	if len(metadata.JWKS) > 0 {
		if err := json.Unmarshal(metadata.JWKS, &jwks); err != nil {
			oauthError(response, http.StatusBadRequest, "invalid_client_metadata")
			return
		}
	}

	token := random()
	f.add(id, &fakeClient{method: metadata.TokenEndpointAuthMethod, jwks: jwks, scope: metadata.Scope})

	f.lock.Lock()
	f.registrations[id] = token
	f.lock.Unlock()

	uri := f.url() + "/register/" + id
	if f.foreignURI {
		uri = "https://elsewhere.example/register/" + id
	}

	writeJSON(response, http.StatusCreated, Registration{
		ClientMetadata:          metadata,
		ClientID:                id,
		RegistrationAccessToken: token,
		RegistrationClientURI:   uri,
	})
}

func (f *fake) registration(response http.ResponseWriter, request *http.Request) {
	id := request.PathValue("id")

	f.lock.Lock()
	held, known := f.registrations[id]
	client := f.clients[id]
	f.lock.Unlock()

	if !known || request.Header.Get("Authorization") != "Bearer "+held {
		oauthError(response, http.StatusUnauthorized, "invalid_token")
		return
	}

	switch request.Method {
	case http.MethodDelete:
		f.lock.Lock()
		delete(f.registrations, id)
		delete(f.clients, id)
		f.lock.Unlock()

		response.WriteHeader(http.StatusNoContent)
	case http.MethodPut:
		metadata := ClientMetadata{}
		if err := json.NewDecoder(request.Body).Decode(&metadata); err != nil {
			oauthError(response, http.StatusBadRequest, "invalid_client_metadata")
			return
		}

		f.lock.Lock()
		client.scope = metadata.Scope
		f.lock.Unlock()

		writeJSON(response, http.StatusOK, Registration{ClientMetadata: metadata, ClientID: id})
	default:
		writeJSON(response, http.StatusOK, Registration{
			ClientMetadata: ClientMetadata{TokenEndpointAuthMethod: client.method, Scope: client.scope},
			ClientID:       id,
		})
	}
}

func writeJSON(response http.ResponseWriter, status int, body any) {
	response.Header().Set("Content-Type", "application/json")
	response.WriteHeader(status)
	_ = json.NewEncoder(response).Encode(body)
}

func oauthError(response http.ResponseWriter, status int, code string) {
	writeJSON(response, status, map[string]string{"error": code, "error_description": code + " from the fake"})
}

func base64Raw(value string) ([]byte, error) {
	return base64.RawURLEncoding.DecodeString(value)
}
