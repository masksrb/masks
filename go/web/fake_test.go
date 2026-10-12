package web

import (
	"crypto/rand"
	"crypto/rsa"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
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

type issuerClient struct {
	secret       string
	redirects    []string
	returnTo     string
	postLogout   string
	registration string
}

type issuedCode struct {
	client, redirect, challenge, nonce, scope, organization string
}

type issuedRefresh struct {
	client, subject, scope, organization string
	spent                                bool
}

type issuer struct {
	t       *testing.T
	server  *httptest.Server
	signing *rsa.PrivateKey

	lock         sync.Mutex
	clients      map[string]*issuerClient
	initial      map[string]string
	codes        map[string]issuedCode
	refreshes    map[string]*issuedRefresh
	live         map[string]string
	revoked      []string
	held         []string
	role         string
	name         string
	expiresIn    int
	refreshed    int
	asked        url.Values
	handshake    url.Values
	ended        url.Values
	deleted      []string
	resource     string
	avatarType   string
	backchannel  bool
	delegateSubs string
	down         bool
}

func newIssuer(t *testing.T) *issuer {
	t.Helper()

	signing, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		t.Fatal(err)
	}

	held := &issuer{
		t: t, signing: signing, clients: map[string]*issuerClient{}, initial: map[string]string{},
		codes: map[string]issuedCode{}, refreshes: map[string]*issuedRefresh{}, live: map[string]string{},
		role: "owner", name: "Ada Lovelace", expiresIn: 3600, avatarType: "image/png", backchannel: true,
	}

	mux := http.NewServeMux()
	mux.HandleFunc("GET /.well-known/openid-configuration", held.discovery)
	mux.HandleFunc("GET /.well-known/jwks.json", held.keys)
	mux.HandleFunc("GET /handshake", held.shake)
	mux.HandleFunc("POST /register", held.register)
	mux.HandleFunc("GET /register/{id}", held.registration)
	mux.HandleFunc("DELETE /register/{id}", held.registration)
	mux.HandleFunc("GET /authorize", held.authorize)
	mux.HandleFunc("POST /token", held.token)
	mux.HandleFunc("GET /userinfo", held.userinfo)
	mux.HandleFunc("POST /revoke", held.revoke)
	mux.HandleFunc("GET /logout", held.endSession)
	mux.HandleFunc("GET /avatars/{subject}/photo", held.avatar)

	held.server = httptest.NewServer(mux)
	t.Cleanup(held.server.Close)

	return held
}

func (f *issuer) url() string {
	return f.server.URL
}

func reply(w http.ResponseWriter, status int, body any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(body)
}

func oauthError(w http.ResponseWriter, status int, code string) {
	reply(w, status, map[string]string{"error": code, "error_description": code + " from the fake"})
}

func (f *issuer) discovery(w http.ResponseWriter, _ *http.Request) {
	base := f.url()

	reply(w, http.StatusOK, map[string]any{
		"issuer":                       base,
		"authorization_endpoint":       base + "/authorize",
		"token_endpoint":               base + "/token",
		"userinfo_endpoint":            base + "/userinfo",
		"jwks_uri":                     base + "/.well-known/jwks.json",
		"revocation_endpoint":          base + "/revoke",
		"end_session_endpoint":         base + "/logout",
		"handshake_endpoint":           base + "/handshake",
		"backchannel_logout_supported": f.backchannel,
	})
}

func (f *issuer) keys(w http.ResponseWriter, _ *http.Request) {
	reply(w, http.StatusOK, jose.JSONWebKeySet{Keys: []jose.JSONWebKey{
		{Key: &f.signing.PublicKey, KeyID: "k1", Algorithm: string(jose.RS256), Use: "sig"},
	}})
}

func (f *issuer) issue(claims map[string]any, typ string) string {
	signer, err := jose.NewSigner(
		jose.SigningKey{Algorithm: jose.RS256, Key: jose.JSONWebKey{Key: f.signing, KeyID: "k1"}},
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

func (f *issuer) accessToken(subject, client, scope, organization, audience string) string {
	claims := map[string]any{
		"iss": f.url(), "sub": subject, "aud": audience, "client_id": client, "scope": scope,
		"exp": time.Now().Add(time.Hour).Unix(), "iat": time.Now().Unix(), "jti": rand.Text(),
	}

	if organization != "" {
		claims["org"] = map[string]string{"id": "o-" + organization, "key": organization, "name": "Acme", "role": f.role}
	}

	token := f.issue(claims, "at+jwt")
	f.live[token] = subject

	return token
}

func (f *issuer) shake(w http.ResponseWriter, r *http.Request) {
	query := r.URL.Query()
	answer, _ := url.Parse(query.Get("return_to"))
	token := rand.Text()
	id := "app-" + rand.Text()

	f.lock.Lock()
	f.handshake = query
	f.initial[token] = id
	f.clients[id] = &issuerClient{returnTo: query.Get("return_to"), postLogout: query.Get("post_logout_redirect_uri"), redirects: query["redirect_uris"]}
	f.lock.Unlock()

	back := answer.Query()
	back.Set("state", query.Get("state"))
	back.Set("iss", f.url())
	back.Set("initial_access_token", token)
	answer.RawQuery = back.Encode()

	http.Redirect(w, r, answer.String(), http.StatusFound)
}

func (f *issuer) register(w http.ResponseWriter, r *http.Request) {
	presented := strings.TrimPrefix(r.Header.Get("Authorization"), "Bearer ")

	f.lock.Lock()
	defer f.lock.Unlock()

	id, known := f.initial[presented]
	delete(f.initial, presented)

	if !known {
		oauthError(w, http.StatusUnauthorized, "invalid_token")
		return
	}

	client := f.clients[id]
	client.secret = rand.Text()
	client.registration = rand.Text()

	reply(w, http.StatusCreated, map[string]any{
		"client_id": id, "client_secret": client.secret, "token_endpoint_auth_method": "client_secret_basic",
		"registration_access_token": client.registration, "registration_client_uri": f.url() + "/register/" + id,
	})
}

func (f *issuer) registration(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")

	f.lock.Lock()
	defer f.lock.Unlock()

	client := f.clients[id]
	if client == nil || r.Header.Get("Authorization") != "Bearer "+client.registration {
		oauthError(w, http.StatusUnauthorized, "invalid_token")
		return
	}

	if r.Method == http.MethodDelete {
		delete(f.clients, id)
		f.deleted = append(f.deleted, id)
		w.WriteHeader(http.StatusNoContent)

		return
	}

	reply(w, http.StatusOK, map[string]any{"client_id": id})
}

func (f *issuer) authenticated(r *http.Request) (string, bool) {
	id, secret, ok := r.BasicAuth()
	if !ok {
		return "", false
	}

	id, _ = url.QueryUnescape(id)
	secret, _ = url.QueryUnescape(secret)

	f.lock.Lock()
	defer f.lock.Unlock()

	client := f.clients[id]

	return id, client != nil && client.secret == secret
}

func (f *issuer) authorize(w http.ResponseWriter, r *http.Request) {
	query := r.URL.Query()

	f.lock.Lock()
	defer f.lock.Unlock()

	f.asked = query
	client := f.clients[query.Get("client_id")]

	if client == nil || !slices.Contains(client.redirects, query.Get("redirect_uri")) {
		oauthError(w, http.StatusBadRequest, "invalid_request")
		return
	}

	var granted []string

	for scope := range strings.FieldsSeq(query.Get("scope")) {
		if !strings.Contains(scope, ":") || slices.Contains(f.held, scope) || strings.HasPrefix(scope, "masks:delegate:") {
			granted = append(granted, scope)
		}
	}

	code := rand.Text()
	f.codes[code] = issuedCode{
		client: query.Get("client_id"), redirect: query.Get("redirect_uri"), challenge: query.Get("code_challenge"),
		nonce: query.Get("nonce"), scope: strings.Join(granted, " "), organization: query.Get("organization"),
	}

	answer, _ := url.Parse(query.Get("redirect_uri"))
	answer.RawQuery = url.Values{"code": {code}, "state": {query.Get("state")}, "iss": {f.url()}}.Encode()

	http.Redirect(w, r, answer.String(), http.StatusFound)
}

func (f *issuer) token(w http.ResponseWriter, r *http.Request) {
	if err := r.ParseForm(); err != nil {
		oauthError(w, http.StatusBadRequest, "invalid_request")
		return
	}

	id, ok := f.authenticated(r)
	if !ok {
		oauthError(w, http.StatusUnauthorized, "invalid_client")
		return
	}

	f.lock.Lock()
	defer f.lock.Unlock()

	form := r.PostForm
	var held *issuedRefresh

	switch form.Get("grant_type") {
	case "authorization_code":
		code, known := f.codes[form.Get("code")]
		delete(f.codes, form.Get("code"))
		sum := sha256.Sum256([]byte(form.Get("code_verifier")))

		if !known || code.client != id || code.redirect != form.Get("redirect_uri") || base64.RawURLEncoding.EncodeToString(sum[:]) != code.challenge {
			oauthError(w, http.StatusBadRequest, "invalid_grant")
			return
		}

		held = &issuedRefresh{client: id, subject: "ada", scope: code.scope, organization: code.organization}
		f.resource = form.Get("resource")

		refresh := rand.Text()
		f.refreshes[refresh] = held
		access := f.accessToken(held.subject, id, held.scope, held.organization, form.Get("resource"))

		body := map[string]any{
			"access_token": access, "token_type": "Bearer", "expires_in": f.expiresIn, "scope": held.scope, "refresh_token": refresh,
			"id_token": f.issue(map[string]any{
				"iss": f.url(), "sub": "ada", "aud": id, "nonce": code.nonce, "sid": "sid-ada",
				"exp": time.Now().Add(15 * time.Minute).Unix(), "iat": time.Now().Unix(),
				"name": "Ada Lovelace", "email": "ada@example.com", "email_verified": true,
				"masks:avatars": map[string]any{"photo": f.url() + "/avatars/ada/photo", "identicon": f.url() + "/avatars/ada/identicon"},
				"tenant":        map[string]string{"uuid": "t-1", "subdomain": "acme", "name": "Acme"},
				"org":           organizationClaim(code.organization, f.role),
			}, "JWT"),
		}

		for scope := range strings.FieldsSeq(code.scope) {
			if provider, found := strings.CutPrefix(scope, "masks:delegate:"); found {
				subject := f.delegateSubs
				if subject == "" {
					subject = "ada"
				}

				body["delegations"] = []map[string]string{{"connection": "c-" + provider, "provider": provider, "subject": subject}}
			}
		}

		reply(w, http.StatusOK, body)
	case "refresh_token":
		if f.down {
			oauthError(w, http.StatusServiceUnavailable, "temporarily_unavailable")
			return
		}

		held = f.refreshes[form.Get("refresh_token")]

		if held == nil || held.client != id || held.spent {
			for _, family := range f.refreshes {
				if held != nil && family.subject == held.subject {
					family.spent = true
				}
			}

			oauthError(w, http.StatusBadRequest, "invalid_grant")

			return
		}

		held.spent = true
		f.refreshed++

		refresh := rand.Text()
		f.refreshes[refresh] = &issuedRefresh{client: id, subject: held.subject, scope: held.scope, organization: held.organization}

		reply(w, http.StatusOK, map[string]any{
			"access_token": f.accessToken(held.subject, id, held.scope, held.organization, form.Get("resource")),
			"token_type":   "Bearer", "expires_in": f.expiresIn, "scope": held.scope, "refresh_token": refresh,
		})
	default:
		oauthError(w, http.StatusBadRequest, "unsupported_grant_type")
	}
}

func organizationClaim(key, role string) any {
	if key == "" {
		return nil
	}

	return map[string]string{"id": "o-" + key, "key": key, "name": "Acme", "role": role}
}

func (f *issuer) userinfo(w http.ResponseWriter, r *http.Request) {
	presented := strings.TrimPrefix(r.Header.Get("Authorization"), "Bearer ")

	f.lock.Lock()
	subject, known := f.live[presented]
	name := f.name
	role := f.role
	f.lock.Unlock()

	if !known {
		oauthError(w, http.StatusUnauthorized, "invalid_token")
		return
	}

	reply(w, http.StatusOK, map[string]any{
		"sub":  subject,
		"name": name,
		"orgs": []map[string]string{
			{"id": "o-acme", "key": "acme", "name": "Acme", "role": role},
			{"id": "o-globex", "key": "globex", "name": "Globex", "role": "member"},
		},
	})
}

func (f *issuer) revoke(w http.ResponseWriter, r *http.Request) {
	if _, ok := f.authenticated(r); !ok {
		oauthError(w, http.StatusUnauthorized, "invalid_client")
		return
	}

	f.lock.Lock()
	f.revoked = append(f.revoked, r.PostFormValue("token"))
	f.lock.Unlock()

	w.WriteHeader(http.StatusOK)
}

func (f *issuer) endSession(w http.ResponseWriter, r *http.Request) {
	query := r.URL.Query()

	f.lock.Lock()
	f.ended = query
	client := f.clients[query.Get("client_id")]
	f.lock.Unlock()

	if client == nil || client.postLogout != query.Get("post_logout_redirect_uri") {
		oauthError(w, http.StatusBadRequest, "invalid_request")
		return
	}

	answer, _ := url.Parse(client.postLogout)
	answer.RawQuery = url.Values{"state": {query.Get("state")}}.Encode()

	http.Redirect(w, r, answer.String(), http.StatusFound)
}

func (f *issuer) avatar(w http.ResponseWriter, r *http.Request) {
	f.lock.Lock()
	_, known := f.live[strings.TrimPrefix(r.Header.Get("Authorization"), "Bearer ")]
	kind := f.avatarType
	f.lock.Unlock()

	if !known {
		w.WriteHeader(http.StatusUnauthorized)
		return
	}

	w.Header().Set("Content-Type", kind)
	_, _ = w.Write([]byte("picture of " + r.PathValue("subject") + " at " + r.URL.Query().Get("size")))
}

func (f *issuer) logoutToken(client, sid string) string {
	return f.issue(map[string]any{
		"iss": f.url(), "aud": client, "iat": time.Now().Unix(), "exp": time.Now().Add(2 * time.Minute).Unix(),
		"jti": rand.Text(), "sid": sid, "events": map[string]any{"http://schemas.openid.net/event/backchannel-logout": map[string]any{}},
	}, "logout+jwt")
}

func (f *issuer) onlyClient() string {
	f.lock.Lock()
	defer f.lock.Unlock()

	for id, client := range f.clients {
		if client.secret != "" {
			return id
		}
	}

	return ""
}
