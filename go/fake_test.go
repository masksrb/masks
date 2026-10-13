package masks

import (
	"crypto/rand"
	"crypto/rsa"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"net/url"
	"slices"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/go-jose/go-jose/v4"
	"github.com/go-jose/go-jose/v4/jwt"
)

type fakeClient struct {
	secret     string
	method     AuthMethod
	jwks       jose.JSONWebKeySet
	scope      string
	refresh    map[string]bool
	redirects  []string
	returnTo   string
	postLogout string
}

type liveToken struct {
	client  string
	subject string
	scope   string
	jkt     string
}

type fakeCode struct {
	client       string
	redirect     string
	challenge    string
	nonce        string
	scope        string
	organization string
	resource     []string
}

type fakePerson struct {
	subject string
	name    string
	email   string
	role    string
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
	live          map[string]liveToken
	enrolledBy    map[string]string
	seen          map[string]url.Values
	staleActive   bool
	authTime      int64
	issuedAs      string
	codes         map[string]fakeCode
	subjects      map[string]string
	person        fakePerson
	declined      bool
	asked         url.Values
	handshake     url.Values
	ended         url.Values
	userinfoName  string
	upstreamDown  bool
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
		live:          map[string]liveToken{},
		enrolledBy:    map[string]string{},
		seen:          map[string]url.Values{},
		codes:         map[string]fakeCode{},
		subjects:      map[string]string{},
		person:        fakePerson{subject: "ada", name: "Ada Lovelace", email: "ada@example.com", role: "owner"},
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
	mux.HandleFunc("POST /introspect", held.introspect)
	mux.HandleFunc("POST /enrollments", held.enroll)
	mux.HandleFunc("DELETE /enrollments/{machine}", held.unenroll)
	mux.HandleFunc("GET /authorize", held.authorize)
	mux.HandleFunc("GET /userinfo", held.userinfo)
	mux.HandleFunc("GET /handshake", held.shake)
	mux.HandleFunc("GET /logout", held.endSession)

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
		"introspection_endpoint":        base + "/introspect",
		"enrollment_endpoint":           base + "/enrollments",
		"authorization_endpoint":        base + "/authorize",
		"userinfo_endpoint":             base + "/userinfo",
		"end_session_endpoint":          base + "/logout",
		"handshake_endpoint":            base + "/handshake",
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
	return f.accessTokenFor(id, id, scope, jkt)
}

func (f *fake) accessTokenFor(subject, id, scope, jkt string) string {
	claims := map[string]any{
		"iss":       f.url(),
		"sub":       subject,
		"aud":       f.audience,
		"exp":       time.Now().Add(time.Hour).Unix(),
		"iat":       time.Now().Unix(),
		"jti":       rand.Text(),
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

	if claims.Method != request.Method || claims.Target != f.url()+request.URL.Path || claims.Hash != "" {
		return "", false
	}

	if f.nonce != "" && claims.Nonce != f.nonce {
		return "", false
	}

	held, err := thumbprint(*parsed.Headers[0].JSONWebKey)

	return held, err == nil
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

	f.seen[request.URL.Path] = request.PostForm
	subject := id

	switch request.PostForm.Get("grant_type") {
	case GrantTokenExchange:
		f.exchange(response, request, id, jkt)
		return
	case GrantClientCredentials:
	case GrantAuthorizationCode:
		f.redeem(response, request, id, client, jkt)
		return
	case GrantRefreshToken:
		presented := request.PostForm.Get("refresh_token")
		if !client.refresh[presented] {
			oauthError(response, http.StatusBadRequest, "invalid_grant")
			return
		}

		delete(client.refresh, presented)
		subject = f.subjects[presented]
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

	if subject == "" {
		subject = id
	}

	refresh := rand.Text()
	client.refresh[refresh] = true
	f.subjects[refresh] = subject

	access := f.accessTokenFor(subject, id, scope, jkt)
	f.live[access] = liveToken{client: id, subject: subject, scope: scope, jkt: jkt}

	body := map[string]any{
		"access_token":  access,
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

	token := rand.Text()
	secret := ""
	if metadata.TokenEndpointAuthMethod == ClientSecretBasic || metadata.TokenEndpointAuthMethod == ClientSecretPost {
		secret = rand.Text()
	}

	f.lock.Lock()
	returnTo, postLogout := "", ""
	if existing := f.clients[id]; existing != nil {
		returnTo, postLogout = existing.returnTo, existing.postLogout
	}
	f.lock.Unlock()

	f.add(id, &fakeClient{method: metadata.TokenEndpointAuthMethod, jwks: jwks, scope: metadata.Scope, secret: secret, redirects: metadata.RedirectURIs, returnTo: returnTo, postLogout: postLogout})

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
		ClientSecret:            secret,
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

func (f *fake) exchange(response http.ResponseWriter, request *http.Request, id, jkt string) {
	form := request.PostForm
	subject, known := f.live[form.Get("subject_token")]

	if !known || form.Get("subject_token_type") != TokenTypeAccessToken {
		oauthError(response, http.StatusBadRequest, "invalid_grant")
		return
	}

	if subject.jkt != "" && subject.jkt != jkt {
		oauthError(response, http.StatusBadRequest, "invalid_dpop_proof")
		return
	}

	if form.Get("requested_token_type") == TokenTypeUpstreamAccessToken && f.upstreamDown {
		oauthError(response, http.StatusServiceUnavailable, "temporarily_unavailable")
		return
	}

	if form.Get("requested_token_type") == TokenTypeUpstreamAccessToken {
		writeJSON(response, http.StatusOK, map[string]any{
			"access_token":      "upstream-" + rand.Text(),
			"issued_token_type": TokenTypeUpstreamAccessToken,
			"token_type":        "Bearer",
			"expires_in":        600,
		})

		return
	}

	scope := form.Get("scope")
	if scope == "" {
		scope = subject.scope
	}

	access := f.accessToken(id, scope, jkt)
	f.live[access] = liveToken{client: id, scope: scope, jkt: jkt}

	issued := TokenTypeAccessToken
	if f.issuedAs != "" {
		issued = f.issuedAs
	}

	body := map[string]any{
		"access_token":      access,
		"issued_token_type": issued,
		"token_type":        "Bearer",
		"expires_in":        300,
		"scope":             scope,
	}

	if jkt != "" {
		body["token_type"] = DPoP
	}

	writeJSON(response, http.StatusOK, body)
}

func (f *fake) introspect(response http.ResponseWriter, request *http.Request) {
	if err := request.ParseForm(); err != nil {
		oauthError(response, http.StatusBadRequest, "invalid_request")
		return
	}

	id, _, ok := f.authenticated(request)
	if !ok {
		oauthError(response, http.StatusUnauthorized, "invalid_client")
		return
	}

	f.lock.Lock()
	defer f.lock.Unlock()

	f.seen[request.URL.Path] = request.PostForm
	held, known := f.live[request.PostForm.Get("token")]

	if !known || held.client != id {
		writeJSON(response, http.StatusOK, map[string]any{"active": false, "scope": "leaked"})
		return
	}

	expiry := time.Now().Add(time.Hour)
	if f.staleActive {
		expiry = time.Now().Add(-time.Hour)
	}

	body := map[string]any{
		"active":     true,
		"scope":      held.scope,
		"client_id":  held.client,
		"sub":        held.client,
		"aud":        []string{f.audience},
		"iss":        f.url(),
		"exp":        expiry.Unix(),
		"token_type": "Bearer",
		"org":        map[string]string{"id": "o-1", "key": "acme", "name": "Acme", "role": "owner"},
	}

	if held.jkt != "" {
		body["token_type"] = DPoP
		body["cnf"] = map[string]string{"jkt": held.jkt}
	}

	writeJSON(response, http.StatusOK, body)
}

func (f *fake) enroll(response http.ResponseWriter, request *http.Request) {
	if err := request.ParseForm(); err != nil {
		oauthError(response, http.StatusBadRequest, "invalid_request")
		return
	}

	app, _, ok := f.authenticated(request)
	if !ok {
		oauthError(response, http.StatusUnauthorized, "invalid_client")
		return
	}

	scope := request.PostForm.Get("scope")
	if scope == "" {
		oauthError(response, http.StatusBadRequest, "invalid_request")
		return
	}

	token := rand.Text()
	machine := "machine-" + rand.Text()

	f.lock.Lock()
	f.seen[request.URL.Path] = request.PostForm
	f.initial[token] = machine
	f.enrolledBy[machine] = app
	f.lock.Unlock()

	writeJSON(response, http.StatusCreated, map[string]any{"initial_access_token": token, "expires_in": 900, "scope": scope})
}

func (f *fake) unenroll(response http.ResponseWriter, request *http.Request) {
	body, err := io.ReadAll(request.Body)
	if err != nil {
		oauthError(response, http.StatusBadRequest, "invalid_request")
		return
	}

	if request.PostForm, err = url.ParseQuery(string(body)); err != nil {
		oauthError(response, http.StatusBadRequest, "invalid_request")
		return
	}

	app, _, ok := f.authenticated(request)
	if !ok {
		oauthError(response, http.StatusUnauthorized, "invalid_client")
		return
	}

	machine := request.PathValue("machine")

	f.lock.Lock()
	defer f.lock.Unlock()

	if f.enrolledBy[machine] != app {
		oauthError(response, http.StatusNotFound, "invalid_request")
		return
	}

	delete(f.clients, machine)
	delete(f.registrations, machine)

	for token, held := range f.live {
		if held.client == machine {
			delete(f.live, token)
		}
	}

	response.WriteHeader(http.StatusNoContent)
}

func (f *fake) authorize(response http.ResponseWriter, request *http.Request) {
	query := request.URL.Query()

	f.lock.Lock()
	defer f.lock.Unlock()

	f.asked = query
	client := f.clients[query.Get("client_id")]
	redirect := query.Get("redirect_uri")

	if client == nil || !slices.Contains(client.redirects, redirect) || query.Get("code_challenge_method") != "S256" {
		oauthError(response, http.StatusBadRequest, "invalid_request")
		return
	}

	answer, _ := url.Parse(redirect)
	back := url.Values{"state": {query.Get("state")}, "iss": {f.url()}}

	if f.declined {
		back.Set("error", "access_denied")
		back.Set("error_description", "the person declined")
	} else {
		code := rand.Text()
		back.Set("code", code)
		f.codes[code] = fakeCode{
			client: query.Get("client_id"), redirect: redirect, challenge: query.Get("code_challenge"),
			nonce: query.Get("nonce"), scope: query.Get("scope"), organization: query.Get("organization"),
			resource: query["resource"],
		}
	}

	answer.RawQuery = back.Encode()
	http.Redirect(response, request, answer.String(), http.StatusFound)
}

func (f *fake) redeem(response http.ResponseWriter, request *http.Request, id string, client *fakeClient, jkt string) {
	form := request.PostForm
	code, known := f.codes[form.Get("code")]
	delete(f.codes, form.Get("code"))

	sum := sha256.Sum256([]byte(form.Get("code_verifier")))

	if !known || code.client != id || code.redirect != form.Get("redirect_uri") ||
		base64.RawURLEncoding.EncodeToString(sum[:]) != code.challenge {
		oauthError(response, http.StatusBadRequest, "invalid_grant")
		return
	}

	subject := f.person.subject
	refresh := rand.Text()
	client.refresh[refresh] = true
	f.subjects[refresh] = subject

	access := f.accessTokenFor(subject, id, code.scope, jkt)
	f.live[access] = liveToken{client: id, subject: subject, scope: code.scope, jkt: jkt}

	body := map[string]any{
		"access_token":  access,
		"token_type":    "Bearer",
		"expires_in":    3600,
		"scope":         code.scope,
		"refresh_token": refresh,
	}

	if jkt != "" {
		body["token_type"] = DPoP
	}

	for scope := range strings.FieldsSeq(code.scope) {
		if provider, found := strings.CutPrefix(scope, ScopeDelegate); found && provider != "" {
			body["delegations"] = []map[string]string{{
				"connection": "connection-" + provider, "provider": provider, "provider_name": "Google", "subject": subject,
			}}
		}
	}

	if slices.Contains(strings.Fields(code.scope), ScopeOpenID) {
		claims := map[string]any{
			"iss": f.url(), "sub": subject, "aud": id, "nonce": code.nonce, "sid": "sid-" + subject,
			"exp": time.Now().Add(15 * time.Minute).Unix(), "iat": time.Now().Unix(),
			"name": f.person.name, "email": f.person.email, "email_verified": true,
			"at_hash": accessTokenHash(access), "tenant": map[string]string{"uuid": "t-1", "subdomain": "acme", "name": "Acme"},
			"masks:avatars": map[string]any{"photo": nil, "identicon": f.url() + "/avatars/" + subject + "/identicon"},
		}

		if f.authTime != 0 {
			claims["auth_time"] = f.authTime
		}

		if code.organization != "" {
			claims["org"] = map[string]string{"id": "o-" + code.organization, "key": code.organization, "name": "Acme", "role": f.person.role}
		}

		body["id_token"] = f.issue(claims, "JWT")
	}

	writeJSON(response, http.StatusOK, body)
}

func (f *fake) userinfo(response http.ResponseWriter, request *http.Request) {
	presented := strings.TrimPrefix(request.Header.Get("Authorization"), "Bearer ")

	f.lock.Lock()
	held, known := f.live[presented]
	name := f.person.name
	if f.userinfoName != "" {
		name = f.userinfoName
	}
	role := f.person.role
	f.lock.Unlock()

	if !known || held.subject == held.client {
		oauthError(response, http.StatusUnauthorized, "invalid_token")
		return
	}

	writeJSON(response, http.StatusOK, map[string]any{
		"sub":  held.subject,
		"name": name,
		"orgs": []map[string]string{
			{"id": "o-acme", "key": "acme", "name": "Acme", "role": role},
			{"id": "o-globex", "key": "globex", "name": "Globex", "role": "member"},
		},
	})
}

func (f *fake) shake(response http.ResponseWriter, request *http.Request) {
	query := request.URL.Query()

	f.lock.Lock()
	f.handshake = query
	declined := f.declined
	f.lock.Unlock()

	answer, err := url.Parse(query.Get("return_to"))
	if err != nil || query.Get("resource") == "" {
		oauthError(response, http.StatusBadRequest, "invalid_request")
		return
	}

	back := answer.Query()
	back.Set("state", query.Get("state"))

	if declined {
		back.Set("error", "access_denied")
		back.Set("error_description", "the person signing in declined")
	} else {
		token := rand.Text()
		id := "app-" + rand.Text()

		f.lock.Lock()
		f.initial[token] = id
		f.clients[id] = &fakeClient{returnTo: query.Get("return_to"), postLogout: query.Get("post_logout_redirect_uri"), refresh: map[string]bool{}}
		f.lock.Unlock()

		back.Set("initial_access_token", token)
		back.Set("iss", f.url())
	}

	answer.RawQuery = back.Encode()
	http.Redirect(response, request, answer.String(), http.StatusFound)
}

func (f *fake) endSession(response http.ResponseWriter, request *http.Request) {
	query := request.URL.Query()

	f.lock.Lock()
	f.ended = query
	client := f.clients[query.Get("client_id")]
	f.lock.Unlock()

	target := query.Get("post_logout_redirect_uri")
	if target == "" {
		writeJSON(response, http.StatusOK, map[string]string{"signed_out": "true"})
		return
	}

	if client == nil || client.postLogout != target {
		oauthError(response, http.StatusBadRequest, "invalid_request")
		return
	}

	answer, _ := url.Parse(target)
	back := answer.Query()
	back.Set("state", query.Get("state"))
	answer.RawQuery = back.Encode()

	http.Redirect(response, request, answer.String(), http.StatusFound)
}
