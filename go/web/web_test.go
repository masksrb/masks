package web

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"net/http/cookiejar"
	"net/http/httptest"
	"net/url"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"testing"
	"time"

	masks "github.com/masksrb/masks/go"
)

type harness struct {
	t       *testing.T
	issuer  *issuer
	app     *App
	server  *httptest.Server
	browser *http.Client
	path    string
	hops    []string
	config  Config
	handler http.Handler
}

func secret() []byte {
	return []byte("0123456789abcdef0123456789abcdef")
}

func newHarness(t *testing.T, change func(*Config)) *harness {
	t.Helper()

	held := &harness{t: t, issuer: newIssuer(t), path: filepath.Join(t.TempDir(), "masks.json")}
	held.server = httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { held.handler.ServeHTTP(w, r) }))
	t.Cleanup(held.server.Close)

	config := Config{
		Issuer:      held.issuer.url(),
		Resource:    held.server.URL,
		Name:        "Catalog",
		Scope:       []string{"openid", "profile", "email", "offline_access", "organization"},
		Secret:      secret(),
		PlainHTTP:   true,
		Credentials: FileCredentials(held.path),
		Privileges: map[string]Privilege{
			"admin":   {Scope: []string{"catalog:admin"}},
			"billing": {Role: []string{"owner", "billing"}},
			"globex":  {Organization: "globex"},
			"read":    {Scope: []string{"catalog:read"}},
		},
		Manages: func(_ *http.Request, person *Person) bool { return person.HasRole("owner") },
	}

	if change != nil {
		change(&config)
	}

	app, err := New(config)
	if err != nil {
		t.Fatal(err)
	}

	held.app = app
	held.config = config

	answer := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		writeJSON(w, http.StatusOK, PersonFrom(r.Context()))
	})

	mux := http.NewServeMux()
	mux.Handle("/auth/", app.Handler())
	mux.Handle("GET /{$}", http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) { io.WriteString(w, "home") }))
	mux.Handle("GET /me", app.Session(answer))
	mux.Handle("/protected", app.Require()(answer))
	mux.Handle("GET /admin", app.Require("admin")(answer))
	mux.Handle("GET /billing", app.Require("billing")(answer))
	mux.Handle("GET /globex", app.Require("globex")(answer))
	mux.Handle("GET /api", app.Protect("read")(answer))
	mux.Handle("GET /either", app.Either()(answer))
	mux.Handle("GET /.well-known/oauth-protected-resource", app.ResourceMetadata())
	mux.HandleFunc("GET /connect", func(w http.ResponseWriter, r *http.Request) {
		if err := app.StartDelegation(w, r, "google", masks.AuthRequest{}); err != nil {
			http.Error(w, err.Error(), http.StatusBadRequest)
		}
	})
	mux.HandleFunc("GET /connect/callback", func(w http.ResponseWriter, r *http.Request) {
		connected, err := app.FinishDelegation(w, r)
		if err != nil {
			http.Error(w, err.Error(), http.StatusBadRequest)
			return
		}

		writeJSON(w, http.StatusOK, map[string]string{"connection": connected.Connection, "secret": connected.Secret})
	})

	held.handler = mux

	jar, _ := cookiejar.New(nil)
	held.browser = &http.Client{Jar: jar, CheckRedirect: func(r *http.Request, _ []*http.Request) error {
		held.hops = append(held.hops, r.URL.String())
		return nil
	}}

	return held
}

func (h *harness) visit(method, path string, headers ...string) (*http.Response, string) {
	h.t.Helper()

	target := path
	if strings.HasPrefix(path, "/") {
		target = h.server.URL + path
	}

	request, err := http.NewRequest(method, target, nil)
	if err != nil {
		h.t.Fatal(err)
	}

	for index := 0; index+1 < len(headers); index += 2 {
		request.Header.Set(headers[index], headers[index+1])
	}

	h.hops = nil

	response, err := h.browser.Do(request)
	if err != nil {
		h.t.Fatal(err)
	}
	defer response.Body.Close()

	body, _ := io.ReadAll(response.Body)

	return response, string(body)
}

func (h *harness) connect() {
	h.t.Helper()

	response, body := h.visit(http.MethodGet, "/auth/handshake")

	if response.StatusCode != http.StatusOK || body != "home" {
		h.t.Fatalf("the handshake ended at %s with %d: %s", response.Request.URL, response.StatusCode, body)
	}
}

func (h *harness) person(path string, headers ...string) *Person {
	h.t.Helper()

	response, body := h.visit(http.MethodGet, path, headers...)
	if response.StatusCode != http.StatusOK {
		h.t.Fatalf("%s answered %d: %s", path, response.StatusCode, body)
	}

	held := &Person{}
	if err := json.Unmarshal([]byte(body), held); err != nil {
		h.t.Fatalf("%s answered %s", path, body)
	}

	return held
}

func (h *harness) cookies() []*http.Cookie {
	parsed, _ := url.Parse(h.server.URL)

	return h.browser.Jar.Cookies(parsed)
}

func TestTheHandshakeConnectsTheAppAndSignsTheManagerIn(t *testing.T) {
	h := newHarness(t, nil)

	response, _ := h.visit(http.MethodGet, "/protected", "Accept", "application/json")
	if response.StatusCode != http.StatusUnauthorized {
		t.Fatalf("expected 401 before the handshake, got %d", response.StatusCode)
	}

	h.connect()

	asked := h.issuer.handshake
	if asked.Get("resource") != h.server.URL || asked.Get("return_to") != h.server.URL+"/auth/handshake/callback" ||
		asked.Get("backchannel_logout_uri") != h.server.URL+"/auth/logout/backchannel" ||
		asked.Get("post_logout_redirect_uri") != h.server.URL+"/auth/logout/return" ||
		!strings.Contains(asked.Get("scope"), "catalog:admin") || !strings.Contains(asked.Get("scope"), "catalog:read") {
		t.Fatalf("unexpected handshake %v", asked)
	}

	stat, err := os.Stat(h.path)
	if err != nil || stat.Mode().Perm() != 0o600 {
		t.Fatalf("the credentials file is %v %v", stat, err)
	}

	saved, _ := os.ReadFile(h.path)
	if !strings.Contains(string(saved), h.issuer.onlyClient()) || !strings.Contains(string(saved), "client_secret") {
		t.Fatalf("unexpected credentials %s", saved)
	}

	person := h.person("/protected")

	if person.Subject != "ada" || person.Name != "Ada Lovelace" || len(person.Organizations) != 2 || person.Tenant.Subdomain != "acme" {
		t.Fatalf("unexpected person %+v", person)
	}

	if h.issuer.resource != h.server.URL || h.issuer.asked.Get("resource") != h.server.URL {
		t.Fatalf("the sign-in did not name the resource: %v", h.issuer.asked)
	}

	connected, err := h.app.Connected(httptest.NewRequest(http.MethodGet, "/", nil))
	if err != nil || !connected {
		t.Fatalf("expected the app to be connected, got %v %v", connected, err)
	}
}

func TestTheSessionNeverCarriesATokenToTheBrowser(t *testing.T) {
	h := newHarness(t, nil)
	h.connect()

	response, body := h.visit(http.MethodGet, "/auth/session")

	if response.StatusCode != http.StatusOK || response.Header.Get("Cache-Control") != "no-store" {
		t.Fatalf("%d %v", response.StatusCode, response.Header)
	}

	for _, leaked := range []string{"eyJ", "refresh", "access_token"} {
		if strings.Contains(body, leaked) {
			t.Fatalf("the session JSON carries %s: %s", leaked, body)
		}
	}

	for _, cookie := range h.cookies() {
		if strings.Contains(cookie.Value, "eyJ") || strings.Contains(cookie.Value, "ada") {
			t.Fatalf("cookie %s is readable: %s", cookie.Name, cookie.Value)
		}
	}

	answer := map[string]any{}
	_ = json.Unmarshal([]byte(body), &answer)

	if answer["signed_in"] != true || answer["subject"] != "ada" || answer["account_url"] != h.issuer.url()+"/" {
		t.Fatalf("unexpected %v", answer)
	}
}

func TestASignInNamesAnOrganizationAndKeepsReturnToLocal(t *testing.T) {
	h := newHarness(t, nil)
	h.connect()

	response, body := h.visit(http.MethodGet, "/auth/?organization=ACME&return_to=/billing")
	if response.StatusCode != http.StatusOK || response.Request.URL.Path != "/billing" {
		t.Fatalf("the sign-in ended at %s with %d: %s", response.Request.URL, response.StatusCode, body)
	}

	if h.issuer.asked.Get("organization") != "acme" {
		t.Fatalf("unexpected %v", h.issuer.asked)
	}

	person := h.person("/me")
	if person.Organization == nil || person.Organization.Key != "acme" || !person.HasRole("owner") || !person.HasPrivilege("billing") {
		t.Fatalf("unexpected %+v", person)
	}

	for _, evil := range []string{"//evil.example/x", "https://evil.example", "/\\evil.example", "/%0d%0aSet-Cookie:x"} {
		response, _ := h.visit(http.MethodGet, "/auth/?return_to="+url.QueryEscape(evil))
		if response.Request.URL.Host != strings.TrimPrefix(h.server.URL, "http://") {
			t.Fatalf("%s sent the browser to %s", evil, response.Request.URL)
		}
	}
}

func TestAPrivilegeAsksMasksOnceAndThenRefuses(t *testing.T) {
	h := newHarness(t, nil)
	h.connect()

	response, body := h.visit(http.MethodGet, "/admin")
	if response.StatusCode != http.StatusForbidden || !strings.Contains(body, "insufficient_scope") {
		t.Fatalf("expected one trip and then 403, got %d at %s: %s", response.StatusCode, response.Request.URL, body)
	}

	if !strings.Contains(h.issuer.asked.Get("scope"), "catalog:admin") {
		t.Fatalf("the trip did not ask for the privilege: %v", h.issuer.asked)
	}

	response, body = h.visit(http.MethodGet, "/admin", "Accept", "application/json")
	if response.StatusCode != http.StatusForbidden || !strings.Contains(body, "privilege_required") || !strings.Contains(body, "privilege=admin") {
		t.Fatalf("expected privilege_required, got %d %s", response.StatusCode, body)
	}

	h.issuer.held = []string{"catalog:admin"}
	h.visit(http.MethodGet, h.app.LoginURL(LoginOptions{Privileges: []string{"admin"}}))

	if person := h.person("/admin"); !person.HasPrivilege("admin") || !person.HasScope("catalog:admin") {
		t.Fatalf("unexpected %+v", person)
	}

	h.issuer.role = "member"
	h.visit(http.MethodGet, "/auth/?organization=acme")

	response, body = h.visit(http.MethodGet, "/billing")
	if response.StatusCode != http.StatusForbidden || !strings.Contains(body, "insufficient_role") {
		t.Fatalf("expected insufficient_role, got %d %s", response.StatusCode, body)
	}

	response, body = h.visit(http.MethodGet, "/globex")
	if response.StatusCode != http.StatusForbidden || !strings.Contains(body, "insufficient_organization") {
		t.Fatalf("expected insufficient_organization, got %d %s", response.StatusCode, body)
	}
}

func TestARefreshIsSharedByRequestsThatArriveTogether(t *testing.T) {
	h := newHarness(t, nil)
	h.issuer.expiresIn = 10
	h.connect()
	h.issuer.name = "Ada King"

	var group sync.WaitGroup
	failures := make(chan string, 8)

	for range 8 {
		group.Add(1)

		go func() {
			defer group.Done()

			request, _ := http.NewRequest(http.MethodGet, h.server.URL+"/me", nil)
			response, err := h.browser.Do(request)
			if err != nil {
				failures <- err.Error()
				return
			}
			defer response.Body.Close()

			held := &Person{}
			if json.NewDecoder(response.Body).Decode(held) != nil || held.Name != "Ada King" {
				failures <- "a request did not see the refreshed identity"
			}
		}()
	}

	group.Wait()
	close(failures)

	for failure := range failures {
		t.Fatal(failure)
	}

	if h.issuer.refreshed != 1 {
		t.Fatalf("expected one refresh, got %d", h.issuer.refreshed)
	}
}

func TestARefreshIsSharedByProcessesThroughTheStore(t *testing.T) {
	h := newHarness(t, func(config *Config) { config.Store = &MemoryStore{} })
	h.issuer.expiresIn = 10
	h.connect()
	h.issuer.name = "Ada King"

	second, err := New(h.config)
	if err != nil {
		t.Fatal(err)
	}

	first := h.handler
	other := second.Session(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		writeJSON(w, http.StatusOK, PersonFrom(r.Context()))
	}))

	h.handler = http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Header.Get("X-Process") == "2" {
			other.ServeHTTP(w, r)
			return
		}

		first.ServeHTTP(w, r)
	})

	var group sync.WaitGroup
	failures := make(chan string, 8)

	for index := range 8 {
		group.Add(1)

		go func() {
			defer group.Done()

			request, _ := http.NewRequest(http.MethodGet, h.server.URL+"/me", nil)
			request.Header.Set("X-Process", strconv.Itoa(1+index%2))

			response, err := h.browser.Do(request)
			if err != nil {
				failures <- err.Error()
				return
			}
			defer response.Body.Close()

			held := &Person{}
			if json.NewDecoder(response.Body).Decode(held) != nil || held.Name != "Ada King" {
				failures <- "a request did not see the refreshed identity"
			}
		}()
	}

	group.Wait()
	close(failures)

	for failure := range failures {
		t.Fatal(failure)
	}

	if h.issuer.refreshed != 1 {
		t.Fatalf("expected one refresh across both processes, got %d", h.issuer.refreshed)
	}
}

func TestASpentRefreshTokenSignsThePersonOut(t *testing.T) {
	h := newHarness(t, nil)
	h.issuer.expiresIn = 10
	h.connect()

	h.issuer.lock.Lock()
	for _, held := range h.issuer.refreshes {
		held.spent = true
	}
	h.issuer.lock.Unlock()

	if person := h.person("/me"); person.SignedIn {
		t.Fatalf("expected the person to be signed out, got %+v", person)
	}
}

func TestSigningOutRevokesAndEndsTheIssuerSession(t *testing.T) {
	h := newHarness(t, func(config *Config) { config.SignOutOfIssuer = true })
	h.connect()

	response, _ := h.visit(http.MethodPost, "/auth/logout", "Origin", "https://evil.example")
	if response.StatusCode != http.StatusForbidden {
		t.Fatalf("a cross-site sign-out was accepted: %d", response.StatusCode)
	}

	response, body := h.visit(http.MethodPost, "/auth/logout", "Origin", h.server.URL)
	if response.StatusCode != http.StatusOK || body != "home" {
		t.Fatalf("the sign-out ended at %s with %d", response.Request.URL, response.StatusCode)
	}

	if len(h.issuer.revoked) != 1 || h.issuer.ended.Get("post_logout_redirect_uri") != h.server.URL+"/auth/logout/return" {
		t.Fatalf("unexpected %v %v", h.issuer.revoked, h.issuer.ended)
	}

	if response, _ := h.visit(http.MethodGet, "/auth/logout/return?state="+url.QueryEscape(h.issuer.ended.Get("state"))); response.StatusCode != http.StatusBadRequest {
		t.Fatalf("a spent farewell was accepted again: %d", response.StatusCode)
	}

	if person := h.person("/me"); person.SignedIn {
		t.Fatal("still signed in")
	}

	if len(h.cookies()) != 0 {
		t.Fatalf("cookies were left behind: %v", h.cookies())
	}
}

func TestABackchannelLogoutEndsTheSession(t *testing.T) {
	h := newHarness(t, nil)
	h.connect()

	var heard *masks.LogoutToken
	h.app.config.LoggedOut = func(_ *http.Request, logout *masks.LogoutToken) error {
		heard = logout
		return nil
	}

	response, _ := http.PostForm(h.server.URL+"/auth/logout/backchannel", url.Values{"logout_token": {"nonsense"}})
	if response.StatusCode != http.StatusBadRequest {
		t.Fatalf("a bad logout token answered %d", response.StatusCode)
	}

	spent := h.issuer.logoutToken(h.issuer.onlyClient(), "sid-ada")

	response, _ = http.PostForm(h.server.URL+"/auth/logout/backchannel", url.Values{"logout_token": {spent}})
	if response.StatusCode != http.StatusOK || heard == nil || heard.SessionID != "sid-ada" {
		t.Fatalf("the logout answered %d with %+v", response.StatusCode, heard)
	}

	if person := h.person("/me"); person.SignedIn {
		t.Fatal("the session outlived its logout")
	}

	h.visit(http.MethodGet, "/auth/")

	replayed, _ := http.PostForm(h.server.URL+"/auth/logout/backchannel", url.Values{"logout_token": {spent}})
	if replayed.StatusCode != http.StatusBadRequest {
		t.Fatalf("a logout token was accepted twice: %d", replayed.StatusCode)
	}

	if person := h.person("/me"); !person.SignedIn {
		t.Fatal("a replayed logout token ended a newer session")
	}

	h.visit(http.MethodGet, "/auth/")

	if person := h.person("/me"); !person.SignedIn {
		t.Fatal("a new sign-in after the logout was refused")
	}
}

func TestAProtectedAPIChecksTheBearerToken(t *testing.T) {
	h := newHarness(t, func(config *Config) { config.ResourceScopes = []string{"catalog:read"} })
	h.connect()

	call := func(token string) (*http.Response, string) {
		request, _ := http.NewRequest(http.MethodGet, h.server.URL+"/api", nil)
		if token != "" {
			request.Header.Set("Authorization", "Bearer "+token)
		}

		response, err := http.DefaultClient.Do(request)
		if err != nil {
			t.Fatal(err)
		}
		defer response.Body.Close()

		body, _ := io.ReadAll(response.Body)

		return response, string(body)
	}

	h.issuer.lock.Lock()
	good := h.issuer.accessToken("ada", "agent", "catalog:read", "acme", h.server.URL)
	narrow := h.issuer.accessToken("ada", "agent", "catalog:list", "", h.server.URL)
	elsewhere := h.issuer.accessToken("ada", "agent", "catalog:read", "", "https://other.example")
	h.issuer.lock.Unlock()

	response, body := call(good)
	if response.StatusCode != http.StatusOK || !strings.Contains(body, `"subject":"ada"`) {
		t.Fatalf("%d %s", response.StatusCode, body)
	}

	response, _ = call(narrow)
	challenge := response.Header.Get("WWW-Authenticate")
	if response.StatusCode != http.StatusForbidden || !strings.Contains(challenge, `error="insufficient_scope"`) ||
		!strings.Contains(challenge, `resource_metadata="`+h.server.URL+`/.well-known/oauth-protected-resource"`) {
		t.Fatalf("%d %s", response.StatusCode, challenge)
	}

	for _, token := range []string{"", elsewhere, "nonsense"} {
		if response, _ := call(token); response.StatusCode != http.StatusUnauthorized || len(response.Header.Values("WWW-Authenticate")) != 2 {
			t.Fatalf("%q answered %d", token, response.StatusCode)
		}
	}

	metadata := map[string]any{}
	response, body = h.visit(http.MethodGet, "/.well-known/oauth-protected-resource")
	_ = json.Unmarshal([]byte(body), &metadata)

	if response.StatusCode != http.StatusOK || metadata["resource"] != h.server.URL || metadata["authorization_servers"].([]any)[0] != h.issuer.url() {
		t.Fatalf("unexpected metadata %s", body)
	}
}

func TestEitherAcceptsASessionOrAToken(t *testing.T) {
	h := newHarness(t, nil)
	h.connect()

	if person := h.person("/either"); person.Subject != "ada" || person.Name == "" {
		t.Fatalf("the session was not accepted: %+v", person)
	}

	h.issuer.lock.Lock()
	token := h.issuer.accessToken("bob", "agent", "", "", h.server.URL)
	h.issuer.lock.Unlock()

	if person := h.person("/either", "Authorization", "Bearer "+token); person.Subject != "bob" {
		t.Fatalf("the token was not preferred: %+v", person)
	}
}

func TestTheAvatarIsProxiedOnlyAsAnImage(t *testing.T) {
	h := newHarness(t, nil)
	h.connect()

	response, body := h.visit(http.MethodGet, "/auth/avatar?size=100")
	if response.StatusCode != http.StatusOK || response.Header.Get("Content-Type") != "image/png" || body != "picture of ada at 128" ||
		response.Header.Get("X-Content-Type-Options") != "nosniff" {
		t.Fatalf("%d %v %s", response.StatusCode, response.Header, body)
	}

	h.issuer.avatarType = "text/html"

	if response, _ := h.visit(http.MethodGet, "/auth/avatar"); response.StatusCode != http.StatusNotFound {
		t.Fatalf("an HTML avatar was served: %d", response.StatusCode)
	}
}

func TestAManagerDisconnectsTheApp(t *testing.T) {
	h := newHarness(t, nil)
	h.connect()
	h.visit(http.MethodGet, "/auth/?organization=acme")
	client := h.issuer.onlyClient()

	response, body := h.visit(http.MethodGet, "/auth/handshake")
	if response.StatusCode != http.StatusOK || !strings.Contains(body, client) {
		t.Fatalf("%d %s", response.StatusCode, body)
	}

	response, _ = h.visit(http.MethodPost, "/auth/handshake/disconnect", "Origin", h.server.URL)
	if len(h.issuer.deleted) != 1 || h.issuer.deleted[0] != client {
		t.Fatalf("the registration was not deleted: %v (%d at %s)", h.issuer.deleted, response.StatusCode, response.Request.URL)
	}

	if saved, _ := os.ReadFile(h.path); strings.Contains(string(saved), client) {
		t.Fatalf("the credentials outlived the disconnect: %s", saved)
	}
}

func TestSomebodyWhoDoesNotManageCannotReconnect(t *testing.T) {
	h := newHarness(t, nil)
	h.connect()
	h.issuer.role = "member"
	h.visit(http.MethodGet, "/auth/?organization=acme")

	if response, _ := h.visit(http.MethodGet, "/auth/handshake"); response.StatusCode != http.StatusForbidden {
		t.Fatalf("expected 403, got %d", response.StatusCode)
	}

	if response, _ := h.visit(http.MethodPost, "/auth/handshake/disconnect", "Origin", h.server.URL); response.StatusCode != http.StatusForbidden {
		t.Fatalf("expected 403, got %d", response.StatusCode)
	}
}

func TestAStaleCallbackRestartsOnceThenRefuses(t *testing.T) {
	h := newHarness(t, nil)
	h.connect()
	h.visit(http.MethodPost, "/auth/logout", "Origin", h.server.URL)

	unfollowed := *h.browser
	unfollowed.CheckRedirect = func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse }

	first, err := unfollowed.Get(h.server.URL + "/auth/callback?state=bogus&code=x")
	if err != nil {
		t.Fatal(err)
	}
	first.Body.Close()

	second, err := unfollowed.Get(h.server.URL + "/auth/callback?state=bogus&code=x")
	if err != nil {
		t.Fatal(err)
	}
	second.Body.Close()

	if first.StatusCode != http.StatusFound || second.StatusCode != http.StatusBadRequest {
		t.Fatalf("expected a restart and then a refusal, got %d and %d", first.StatusCode, second.StatusCode)
	}
}

func TestAServerSideStoreRotatesTheSessionOnSignIn(t *testing.T) {
	store := &MemoryStore{}
	h := newHarness(t, func(config *Config) { config.Sessions = store })

	h.visit(http.MethodGet, "/auth/handshake")
	before := h.cookies()

	h.visit(http.MethodGet, "/auth/")
	after := h.cookies()

	if len(after) != 1 || len(after[0].Value) > 200 || (len(before) == 1 && before[0].Value == after[0].Value) {
		t.Fatalf("unexpected cookies %v then %v", before, after)
	}

	if person := h.person("/me"); !person.SignedIn {
		t.Fatal("the stored session was not read")
	}

	sessions := store.entries.len()

	if sessions != 1 {
		t.Fatalf("the old session was kept: %d", sessions)
	}
}

func TestADelegationIsConnectedByThePersonSignedIn(t *testing.T) {
	h := newHarness(t, func(config *Config) {
		config.Delegates = true
		config.DelegationPath = "/connect/callback"
	})
	h.connect()

	if !strings.Contains(h.issuer.handshake.Get("scope"), "masks:delegate:") ||
		!strings.Contains(strings.Join(h.issuer.handshake["redirect_uris"], " "), h.server.URL+"/connect/callback") {
		t.Fatalf("unexpected handshake %v", h.issuer.handshake)
	}

	response, body := h.visit(http.MethodGet, "/connect")
	if response.StatusCode != http.StatusOK || !strings.Contains(body, `"connection":"c-google"`) {
		t.Fatalf("%d %s", response.StatusCode, body)
	}

	h.issuer.delegateSubs = "mallory"

	if response, _ := h.visit(http.MethodGet, "/connect"); response.StatusCode != http.StatusBadRequest {
		t.Fatalf("a connection finished by someone else was accepted: %d", response.StatusCode)
	}
}

func TestAnIssuerPerRequestKeepsTenantsApart(t *testing.T) {
	other := newIssuer(t)
	stores := map[string]CredentialStore{}
	dir := t.TempDir()

	h := newHarness(t, func(config *Config) {
		first := config.Issuer
		config.Issuer = ""
		config.IssuerFor = func(r *http.Request) (string, error) {
			if cookie, err := r.Cookie("tenant"); err == nil && cookie.Value == "other" {
				return other.url(), nil
			}

			return first, nil
		}
		config.Credentials = credentialsFunc(func(r *http.Request) CredentialStore {
			key := "first"
			if cookie, err := r.Cookie("tenant"); err == nil {
				key = cookie.Value
			}

			if stores[key] == nil {
				stores[key] = FileCredentials(filepath.Join(dir, key+".json"))
			}

			return stores[key]
		})
	})

	h.connect()

	parsed, _ := url.Parse(h.server.URL)
	h.browser.Jar.SetCookies(parsed, []*http.Cookie{{Name: "tenant", Value: "other", Path: "/"}})

	if person := h.person("/me"); person.SignedIn {
		t.Fatal("a session from one issuer was accepted for another")
	}

	h.connect()

	if other.onlyClient() == "" || h.person("/me").Subject != "ada" {
		t.Fatal("the second tenant did not connect")
	}
}

type credentialsFunc func(*http.Request) CredentialStore

func (f credentialsFunc) Load(r *http.Request) (*Credentials, error) { return f(r).Load(r) }
func (f credentialsFunc) Save(r *http.Request, held *Credentials) error {
	return f(r).Save(r, held)
}
func (f credentialsFunc) Forget(r *http.Request) error { return f(r).Forget(r) }

func TestTheCookieIsHardenedAndSealed(t *testing.T) {
	app, err := New(Config{Issuer: "https://id.example", Resource: "https://app.example", Secret: secret()})
	if err != nil {
		t.Fatal(err)
	}

	recorder := httptest.NewRecorder()
	request := httptest.NewRequest(http.MethodGet, "https://app.example/", nil)
	held := &state{data: &session{ReturnTo: "/x", Identity: &masks.Identity{Name: strings.Repeat("Ada ", 3000)}}, dirty: true}

	if err := app.commit(recorder, request, held); err != nil {
		t.Fatal(err)
	}

	cookies := recorder.Result().Cookies()
	if len(cookies) < 2 {
		t.Fatalf("a large session was not split: %d cookies", len(cookies))
	}

	for _, cookie := range cookies {
		if !strings.HasPrefix(cookie.Name, "__Host-masks") || !cookie.Secure || !cookie.HttpOnly || cookie.SameSite != http.SameSiteLaxMode || cookie.Path != "/" || cookie.Domain != "" {
			t.Fatalf("unexpected cookie %+v", cookie)
		}
	}

	reread := httptest.NewRequest(http.MethodGet, "https://app.example/", nil)
	for _, cookie := range cookies {
		reread.AddCookie(cookie)
	}

	loaded, err := app.load(reread)
	if err != nil || loaded.data.ReturnTo != "/x" || !strings.HasPrefix(loaded.data.Identity.Name, "Ada Ada") {
		t.Fatalf("the split session did not come back: %v", err)
	}

	tampered := httptest.NewRequest(http.MethodGet, "https://app.example/", nil)
	tampered.AddCookie(&http.Cookie{Name: "__Host-masks", Value: cookies[0].Value[:40] + "A" + cookies[0].Value[41:]})

	if loaded, _ := app.load(tampered); loaded.data.ReturnTo != "" {
		t.Fatal("a tampered cookie was read")
	}

	rotated, err := New(Config{Issuer: "https://id.example", Resource: "https://app.example", Secret: []byte(strings.Repeat("n", 32)), PreviousSecrets: [][]byte{secret()}})
	if err != nil {
		t.Fatal(err)
	}

	if loaded, _ := rotated.load(reread); loaded.data.ReturnTo != "/x" {
		t.Fatal("a previous secret no longer opens the session")
	}

	if _, err := New(Config{Issuer: "https://id.example", Resource: "https://app.example", Secret: []byte("short")}); err == nil {
		t.Fatal("a short secret was accepted")
	}
}

func TestLocalPathsOnly(t *testing.T) {
	for value, want := range map[string]string{
		"/billing?tab=2":       "/billing?tab=2",
		"//evil.example":       "",
		"https://evil.example": "",
		"/\\evil.example":      "",
		"/a\r\nb":              "",
		"relative":             "",
		"/%2F%2Fevil.example":  "",
	} {
		if held := localPath(value); held != want {
			t.Errorf("%q became %q", value, held)
		}
	}
}

func TestAStoreThatFailsRefusesAProofWith503(t *testing.T) {
	h := newHarness(t, func(config *Config) { config.Store = failing{} })

	key, err := masks.GenerateKey()
	if err != nil {
		t.Fatal(err)
	}

	token := h.issuer.issue(map[string]any{
		"iss": h.issuer.url(), "sub": "agent", "aud": h.server.URL, "scope": "catalog:read", "jti": "1",
		"exp": time.Now().Add(time.Hour).Unix(), "iat": time.Now().Unix(), "cnf": map[string]string{"jkt": key.Thumbprint()},
	}, "at+jwt")

	proof, err := key.Proof(http.MethodGet, h.server.URL+"/api", token, "")
	if err != nil {
		t.Fatal(err)
	}

	request, _ := http.NewRequest(http.MethodGet, h.server.URL+"/api", nil)
	request.Header.Set("Authorization", "DPoP "+token)
	request.Header.Set("DPoP", proof)

	response, err := http.DefaultClient.Do(request)
	if err != nil {
		t.Fatal(err)
	}
	response.Body.Close()

	if response.StatusCode != http.StatusServiceUnavailable {
		t.Fatalf("expected 503, got %d", response.StatusCode)
	}
}

func TestASessionOutlivesAnIssuerThatIsDown(t *testing.T) {
	h := newHarness(t, nil)
	h.issuer.expiresIn = 10
	h.connect()
	h.issuer.down = true

	if person := h.person("/me"); person.SignedIn {
		t.Fatal("a refresh that masks could not answer still signed the person in")
	}

	h.issuer.down = false

	if person := h.person("/me"); !person.SignedIn || person.Subject != "ada" {
		t.Fatal("the session was forgotten while masks was down")
	}
}

func TestACrossSiteSignOutIsRefusedForEveryMethod(t *testing.T) {
	h := newHarness(t, nil)
	h.connect()

	for _, method := range []string{http.MethodGet, http.MethodPost, http.MethodDelete} {
		if response, _ := h.visit(method, "/auth/logout?everywhere=1", "Sec-Fetch-Site", "cross-site"); response.StatusCode != http.StatusForbidden {
			t.Fatalf("a cross-site %s answered %d", method, response.StatusCode)
		}
	}

	if person := h.person("/me"); !person.SignedIn {
		t.Fatal("a cross-site request signed the person out")
	}
}

func TestARefreshThatPanicsReleasesTheOthersWaiting(t *testing.T) {
	held := &flights{}

	func() {
		defer func() { _ = recover() }()

		held.do("token", func() *renewal { panic("boom") })
	}()

	done := make(chan *renewal, 1)

	go func() {
		done <- held.do("token", func() *renewal { return &renewal{Outcome: renewed} })
	}()

	select {
	case result := <-done:
		if result.Outcome != renewed {
			t.Fatalf("the next refresh failed: %v", result.Outcome)
		}
	case <-time.After(time.Second):
		t.Fatal("the next refresh waited forever")
	}
}

type failing struct{}

func (failing) Add(context.Context, string, []byte, time.Duration) (bool, error) {
	return false, errors.New("redis is down")
}

func (failing) Get(context.Context, string) ([]byte, error) { return nil, errors.New("redis is down") }

func (failing) Set(context.Context, string, []byte, time.Duration) error {
	return errors.New("redis is down")
}

func (failing) Delete(context.Context, string) error { return errors.New("redis is down") }

type readOnly struct{ CredentialStore }

func (readOnly) Writable(*http.Request) error { return errors.New("read-only file system") }

func TestAStoreThatCannotSaveLeavesNoClientBehind(t *testing.T) {
	h := newHarness(t, func(config *Config) { config.Credentials = readOnly{config.Credentials} })

	response, _ := h.visit(http.MethodGet, "/auth/handshake")

	if response.StatusCode != http.StatusInternalServerError || h.issuer.onlyClient() != "" {
		t.Fatalf("expected 500 and no client, got %d and %q", response.StatusCode, h.issuer.onlyClient())
	}
}

func TestCredentialsAreHeldToTheirIssuer(t *testing.T) {
	_, err := New(Config{
		IssuerFor: func(*http.Request) (string, error) { return "https://id.example", nil },
		Resource:  "https://app.example",
		Secret:    secret(),
	})
	if err == nil {
		t.Fatal("an issuer per request was allowed to share one credentials file")
	}

	h := newHarness(t, nil)
	h.connect()

	saved, err := os.ReadFile(h.path)
	if err != nil {
		t.Fatal(err)
	}

	held := &Credentials{}
	if err := json.Unmarshal(saved, held); err != nil || held.Issuer != h.issuer.url() {
		t.Fatalf("the credentials do not name their issuer: %s", saved)
	}

	held.Issuer = "https://elsewhere.example"
	h.app.config.Credentials = FileCredentials(h.path)
	if err := h.app.config.Credentials.Save(nil, held); err != nil {
		t.Fatal(err)
	}

	if response, _ := h.visit(http.MethodGet, "/me"); response.StatusCode == http.StatusOK {
		t.Fatal("credentials from another issuer were used")
	}

	held.Issuer = ""
	if err := h.app.config.Credentials.Save(nil, held); err != nil {
		t.Fatal(err)
	}

	if person := h.person("/me"); !person.SignedIn {
		t.Fatal("credentials without an issuer were refused for the only issuer")
	}
}

type counting struct {
	MemoryStore
	lock sync.Mutex
	gets int
}

func (c *counting) Get(ctx context.Context, key string) ([]byte, error) {
	c.lock.Lock()
	c.gets++
	c.lock.Unlock()

	return c.MemoryStore.Get(ctx, key)
}

func (c *counting) reset() int {
	c.lock.Lock()
	defer c.lock.Unlock()

	held := c.gets
	c.gets = 0

	return held
}

func TestASessionIsLoadedOnceWhenSessionWrapsEveryRoute(t *testing.T) {
	sessions := &counting{}
	h := newHarness(t, func(config *Config) { config.Sessions = sessions })
	h.handler = h.app.Session(h.handler)

	h.connect()

	if person := h.person("/protected"); !person.SignedIn {
		t.Fatal("the guarded route did not see the person")
	}

	sessions.reset()

	response, _ := h.visit(http.MethodGet, "/protected")
	if response.StatusCode != http.StatusOK {
		t.Fatalf("the guarded route answered %d", response.StatusCode)
	}

	if loaded := sessions.reset(); loaded != 1 {
		t.Fatalf("one request read the session %d times", loaded)
	}

	request := httptest.NewRequest(http.MethodGet, h.server.URL+"/protected", nil)
	request.AddCookie(&http.Cookie{Name: "masks", Value: "stale"})
	recorder := httptest.NewRecorder()
	h.handler.ServeHTTP(recorder, request)

	var written []string
	for _, line := range recorder.Header().Values("Set-Cookie") {
		if strings.HasPrefix(line, "masks=") {
			written = append(written, line)
		}
	}

	if recorder.Code != http.StatusFound || len(written) != 1 || strings.HasPrefix(written[0], "masks=;") {
		t.Fatalf("a stale cookie answered %d and wrote %v", recorder.Code, written)
	}
}

func TestATokenIsCheckedOnlyForAnHTTPSResource(t *testing.T) {
	app, err := New(Config{Issuer: "https://id.example", Resource: "http://app.example", Secret: secret()})
	if err != nil {
		t.Fatal(err)
	}

	recorder := httptest.NewRecorder()
	app.ResourceMetadata().ServeHTTP(recorder, httptest.NewRequest(http.MethodGet, "/.well-known/oauth-protected-resource", nil))

	if recorder.Code == http.StatusOK {
		t.Fatal("an http resource was described")
	}
}

func TestASecondSaveStillClearsTheChunksTheBrowserHeld(t *testing.T) {
	app, err := New(Config{Issuer: "https://id.example", Resource: "https://app.example", Secret: secret()})
	if err != nil {
		t.Fatal(err)
	}

	request := httptest.NewRequest(http.MethodGet, "/", nil)
	for _, name := range []string{"__Host-masks", "__Host-masks-1", "__Host-masks-2"} {
		request.AddCookie(&http.Cookie{Name: name, Value: "stale"})
	}

	held, err := app.load(request)
	if err != nil {
		t.Fatal(err)
	}

	recorder := httptest.NewRecorder()
	held.change().ReturnTo = "/first"

	if err := app.commit(recorder, request, held); err != nil {
		t.Fatal(err)
	}

	held.change().ReturnTo = "/second"

	if err := app.commit(recorder, request, held); err != nil {
		t.Fatal(err)
	}

	cleared := map[string]bool{}
	kept := 0

	for _, cookie := range (&http.Response{Header: recorder.Header()}).Cookies() {
		switch {
		case cookie.MaxAge < 0:
			cleared[cookie.Name] = true
		case cookie.Name == "__Host-masks":
			kept++
		}
	}

	if kept != 1 || !cleared["__Host-masks-1"] || !cleared["__Host-masks-2"] {
		t.Fatalf("the second save left %v", recorder.Header().Values("Set-Cookie"))
	}
}

type discoveries struct {
	lock  sync.Mutex
	count int
	gate  chan struct{}
	fail  bool
}

func (d *discoveries) RoundTrip(r *http.Request) (*http.Response, error) {
	if strings.HasSuffix(r.URL.Path, "/.well-known/openid-configuration") {
		d.lock.Lock()
		d.count++
		gate, fail := d.gate, d.fail
		d.lock.Unlock()

		if gate != nil {
			<-gate
		}

		if fail {
			return nil, errors.New("masks is down")
		}
	}

	return http.DefaultTransport.RoundTrip(r)
}

func (d *discoveries) seen() int {
	d.lock.Lock()
	defer d.lock.Unlock()

	return d.count
}

func TestAStaleIssuerIsServedWhileOneRefreshRunsBehindIt(t *testing.T) {
	counted := &discoveries{}
	h := newHarness(t, func(config *Config) { config.HTTPClient = &http.Client{Transport: counted} })
	h.connect()

	request := httptest.NewRequest(http.MethodGet, "/", nil)

	first, err := h.app.issuerFor(request)
	if err != nil {
		t.Fatal(err)
	}

	before := counted.seen()
	gate := make(chan struct{})

	counted.lock.Lock()
	counted.gate = gate
	counted.lock.Unlock()

	h.app.lock.Lock()
	h.app.issuers[h.issuer.url()].at = time.Now().Add(-2 * discoveryLifetime)
	h.app.lock.Unlock()

	for range 5 {
		served, err := h.app.issuerFor(request)
		if err != nil || served != first {
			t.Fatalf("a stale issuer was not served while it refreshed: %v", err)
		}
	}

	close(gate)

	deadline := time.Now().Add(5 * time.Second)
	for {
		h.app.lock.Lock()
		fresh := h.app.issuers[h.issuer.url()].pending == nil
		h.app.lock.Unlock()

		if fresh || time.Now().After(deadline) {
			break
		}

		time.Sleep(10 * time.Millisecond)
	}

	if refreshed := counted.seen() - before; refreshed != 1 {
		t.Fatalf("five requests ran %d discoveries", refreshed)
	}

	if served, _ := h.app.issuerFor(request); served == first {
		t.Fatal("the refreshed issuer was not kept")
	}
}

func TestAnIssuerThatIsDownIsAskedAgainOnlyAfterAPause(t *testing.T) {
	counted := &discoveries{fail: true}
	h := newHarness(t, func(config *Config) { config.HTTPClient = &http.Client{Transport: counted} })
	request := httptest.NewRequest(http.MethodGet, "/", nil)

	for range 3 {
		if _, err := h.app.issuerFor(request); err == nil {
			t.Fatal("an issuer that is down was discovered")
		}
	}

	if counted.seen() != 1 {
		t.Fatalf("three requests ran %d discoveries while masks was down", counted.seen())
	}

	counted.lock.Lock()
	counted.fail = false
	counted.lock.Unlock()

	h.app.lock.Lock()
	h.app.issuers[h.issuer.url()].retry = time.Now()
	h.app.lock.Unlock()

	if _, err := h.app.issuerFor(request); err != nil {
		t.Fatalf("the issuer was not discovered once it came back: %v", err)
	}
}

func TestTheIssuerCacheIsBounded(t *testing.T) {
	counted := &discoveries{fail: true}
	app, err := New(Config{
		IssuerFor:   func(r *http.Request) (string, error) { return "https://" + r.Host, nil },
		Resource:    "https://app.example",
		Secret:      secret(),
		Credentials: FileCredentials(filepath.Join(t.TempDir(), "masks.json")),
		HTTPClient:  &http.Client{Transport: counted},
	})
	if err != nil {
		t.Fatal(err)
	}

	for index := range remembered + 50 {
		request := httptest.NewRequest(http.MethodGet, "/", nil)
		request.Host = "tenant" + strconv.Itoa(index) + ".example"
		_, _ = app.issuerFor(request)
	}

	app.lock.Lock()
	held := len(app.issuers)
	app.lock.Unlock()

	if held > remembered {
		t.Fatalf("the cache holds %d issuers", held)
	}
}

func TestAPersonChecksAPrivilegeOfTheirOwn(t *testing.T) {
	person := &Person{SignedIn: true, Scopes: []string{"catalog:read"}, Organization: &masks.Organization{Key: "acme", Role: "member"}}

	if !person.Holds(Privilege{Scope: []string{"catalog:read"}}) || person.Holds(Privilege{Scope: []string{"catalog:admin"}}) {
		t.Fatal("Holds misread the scopes")
	}

	var refused *Forbidden

	if err := person.Member(Privilege{Role: []string{"owner"}}); !errors.As(err, &refused) || refused.Code != "insufficient_role" {
		t.Fatalf("a member was taken for an owner: %v", err)
	}

	if err := person.Member(Privilege{Organization: "globex"}); !errors.As(err, &refused) || refused.Code != "insufficient_organization" {
		t.Fatalf("acme was taken for globex: %v", err)
	}

	if err := person.Member(Privilege{Role: []string{"member"}, Organization: "acme"}); err != nil {
		t.Fatalf("a member of acme was refused: %v", err)
	}

	nobody := PersonFrom(context.Background())

	if nobody.Holds(Privilege{}) || nobody.Member(Privilege{}) == nil {
		t.Fatal("somebody signed out holds a privilege")
	}
}

func TestTheNameCanBeChosenForEachRequest(t *testing.T) {
	app, err := New(Config{
		Issuer:   "https://id.example",
		Resource: "https://app.example",
		Secret:   secret(),
		NameFor:  func(r *http.Request) string { return "Catalog for " + r.Host },
	})
	if err != nil {
		t.Fatal(err)
	}

	if name := app.nameFor(httptest.NewRequest(http.MethodGet, "https://acme.app.example/", nil)); name != "Catalog for acme.app.example" {
		t.Fatalf("the name was %q", name)
	}
}
