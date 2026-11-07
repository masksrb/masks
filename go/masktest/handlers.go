package masktest

import (
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"io"
	"net/http"
	"net/url"
	"slices"
	"strings"
	"time"

	"github.com/go-jose/go-jose/v4"
	"github.com/go-jose/go-jose/v4/jwt"
)

func (f *Fake) discovery(response http.ResponseWriter, _ *http.Request) {
	base := f.URL()

	WriteJSON(response, http.StatusOK, map[string]any{
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

func (f *Fake) keys(response http.ResponseWriter, _ *http.Request) {
	WriteJSON(response, http.StatusOK, jose.JSONWebKeySet{Keys: []jose.JSONWebKey{
		{Key: &f.signing.PublicKey, KeyID: f.kid, Algorithm: string(jose.RS256), Use: "sig"},
	}})
}

func (f *Fake) authenticated(request *http.Request) (string, *Client, bool) {
	f.lock.Lock()
	defer f.lock.Unlock()

	if id, secret, ok := request.BasicAuth(); ok {
		id, _ = url.QueryUnescape(id)
		secret, _ = url.QueryUnescape(secret)
		client := f.clients[id]

		return id, client, client != nil && client.Method == ClientSecretBasic && client.Secret == secret
	}

	id := request.PostForm.Get("client_id")
	client := f.clients[id]

	if client == nil {
		return id, nil, false
	}

	switch client.Method {
	case ClientSecretPost:
		return id, client, request.PostForm.Get("client_secret") == client.Secret
	case NoAuth:
		return id, client, true
	case PrivateKeyJWT:
		return id, client, f.asserted(request, id, client)
	}

	return id, client, false
}

func (f *Fake) asserted(request *http.Request, id string, client *Client) bool {
	if request.PostForm.Get("client_assertion_type") != assertionType {
		return false
	}

	parsed, err := jwt.ParseSigned(request.PostForm.Get("client_assertion"), []jose.SignatureAlgorithm{jose.ES256})
	if err != nil {
		return false
	}

	keys := client.JWKS.Key(parsed.Headers[0].KeyID)
	if len(keys) != 1 {
		return false
	}

	claims := jwt.Claims{}

	if parsed.Claims(keys[0].Key, &claims) != nil || claims.Issuer != id || claims.Subject != id || claims.ID == "" {
		return false
	}

	if claims.ValidateWithLeeway(jwt.Expected{AnyAudience: jwt.Audience{f.URL(), f.URL() + "/token"}, Time: time.Now()}, 0) != nil {
		return false
	}

	if f.assertions[claims.ID] {
		return false
	}

	f.assertions[claims.ID] = true

	return true
}

func (f *Fake) proof(request *http.Request) (string, bool) {
	presented := request.Header.Get(dpopHeader)
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

	if claims.Method != request.Method || claims.Target != f.URL()+request.URL.Path || claims.Hash != "" {
		return "", false
	}

	if f.Nonce != "" && claims.Nonce != f.Nonce {
		return "", false
	}

	held, err := thumbprint(*parsed.Headers[0].JSONWebKey)

	return held, err == nil
}

func (f *Fake) token(response http.ResponseWriter, request *http.Request) {
	if err := request.ParseForm(); err != nil {
		OAuthError(response, http.StatusBadRequest, "invalid_request")
		return
	}

	jkt, ok := f.proof(request)
	if !ok {
		if f.Nonce != "" {
			response.Header().Set("DPoP-Nonce", f.Nonce)
			OAuthError(response, http.StatusBadRequest, "use_dpop_nonce")

			return
		}

		OAuthError(response, http.StatusBadRequest, "invalid_dpop_proof")

		return
	}

	id, client, ok := f.authenticated(request)
	if !ok {
		OAuthError(response, http.StatusUnauthorized, "invalid_client")
		return
	}

	f.lock.Lock()
	defer f.lock.Unlock()

	f.Seen[request.URL.Path] = request.PostForm
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
			OAuthError(response, http.StatusBadRequest, "invalid_grant")
			return
		}

		delete(client.refresh, presented)
		subject = f.subjects[presented]
	case GrantDeviceCode:
		if f.Pending > 0 {
			f.Pending--

			if !f.slowed {
				f.slowed = true
				OAuthError(response, http.StatusBadRequest, "slow_down")

				return
			}

			OAuthError(response, http.StatusBadRequest, "authorization_pending")

			return
		}
	default:
		OAuthError(response, http.StatusBadRequest, "unsupported_grant_type")
		return
	}

	scope := request.PostForm.Get("scope")
	if scope == "" {
		scope = client.Scope
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
		body["token_type"] = dpopHeader
	}

	WriteJSON(response, http.StatusOK, body)
}

func (f *Fake) device(response http.ResponseWriter, request *http.Request) {
	if err := request.ParseForm(); err != nil {
		OAuthError(response, http.StatusBadRequest, "invalid_request")
		return
	}

	id, _, ok := f.authenticated(request)
	if !ok || request.PostForm.Get("client_id") != id {
		OAuthError(response, http.StatusUnauthorized, "invalid_client")
		return
	}

	WriteJSON(response, http.StatusOK, map[string]any{
		"device_code":      "device-code",
		"user_code":        "ABCD EFGH",
		"verification_uri": f.URL() + "/device",
		"expires_in":       600,
		"interval":         0,
	})
}

func (f *Fake) revoke(response http.ResponseWriter, request *http.Request) {
	if err := request.ParseForm(); err != nil {
		OAuthError(response, http.StatusBadRequest, "invalid_request")
		return
	}

	if _, _, ok := f.authenticated(request); !ok {
		OAuthError(response, http.StatusUnauthorized, "invalid_client")
		return
	}

	f.lock.Lock()
	f.Revoked = append(f.Revoked, request.PostForm.Get("token"))
	f.lock.Unlock()

	response.WriteHeader(http.StatusOK)
}

func (f *Fake) register(response http.ResponseWriter, request *http.Request) {
	presented := strings.TrimPrefix(request.Header.Get("Authorization"), "Bearer ")

	f.lock.Lock()
	id, known := f.Initial[presented]
	if known {
		delete(f.Initial, presented)
	}
	f.lock.Unlock()

	if !known {
		OAuthError(response, http.StatusUnauthorized, "invalid_token")
		return
	}

	metadata := map[string]any{}
	if err := json.NewDecoder(request.Body).Decode(&metadata); err != nil {
		OAuthError(response, http.StatusBadRequest, "invalid_client_metadata")
		return
	}

	jwks := jose.JSONWebKeySet{}
	if raw, found := metadata["jwks"]; found && raw != nil {
		encoded, _ := json.Marshal(raw)
		if err := json.Unmarshal(encoded, &jwks); err != nil {
			OAuthError(response, http.StatusBadRequest, "invalid_client_metadata")
			return
		}
	}

	method, _ := metadata["token_endpoint_auth_method"].(string)
	scope, _ := metadata["scope"].(string)

	token := rand.Text()
	secret := ""
	if method == ClientSecretBasic || method == ClientSecretPost {
		secret = rand.Text()
	}

	f.lock.Lock()
	returnTo, postLogout := "", ""
	if existing := f.clients[id]; existing != nil {
		returnTo, postLogout = existing.returnTo, existing.postLogout
	}
	f.lock.Unlock()

	f.Add(id, &Client{Method: method, JWKS: jwks, Scope: scope, Secret: secret, redirects: stringsOf(metadata["redirect_uris"]), returnTo: returnTo, postLogout: postLogout})

	f.lock.Lock()
	f.registrations[id] = token
	f.lock.Unlock()

	uri := f.URL() + "/register/" + id
	if f.ForeignURI {
		uri = "https://elsewhere.example/register/" + id
	}

	metadata["client_id"] = id
	metadata["registration_access_token"] = token
	metadata["registration_client_uri"] = uri
	if secret != "" {
		metadata["client_secret"] = secret
	}

	WriteJSON(response, http.StatusCreated, metadata)
}

func stringsOf(value any) []string {
	items, _ := value.([]any)
	held := make([]string, 0, len(items))

	for _, item := range items {
		if text, ok := item.(string); ok {
			held = append(held, text)
		}
	}

	return held
}

func (f *Fake) registration(response http.ResponseWriter, request *http.Request) {
	id := request.PathValue("id")

	f.lock.Lock()
	held, known := f.registrations[id]
	client := f.clients[id]
	f.lock.Unlock()

	if !known || request.Header.Get("Authorization") != "Bearer "+held {
		OAuthError(response, http.StatusUnauthorized, "invalid_token")
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
		metadata := map[string]any{}
		if err := json.NewDecoder(request.Body).Decode(&metadata); err != nil {
			OAuthError(response, http.StatusBadRequest, "invalid_client_metadata")
			return
		}

		scope, _ := metadata["scope"].(string)

		f.lock.Lock()
		client.Scope = scope
		f.lock.Unlock()

		metadata["client_id"] = id
		WriteJSON(response, http.StatusOK, metadata)
	default:
		body := map[string]any{"client_id": id}
		if client.Method != "" {
			body["token_endpoint_auth_method"] = client.Method
		}
		if client.Scope != "" {
			body["scope"] = client.Scope
		}

		WriteJSON(response, http.StatusOK, body)
	}
}

func (f *Fake) exchange(response http.ResponseWriter, request *http.Request, id, jkt string) {
	form := request.PostForm
	subject, known := f.live[form.Get("subject_token")]

	if !known || form.Get("subject_token_type") != TokenTypeAccessToken {
		OAuthError(response, http.StatusBadRequest, "invalid_grant")
		return
	}

	if subject.jkt != "" && subject.jkt != jkt {
		OAuthError(response, http.StatusBadRequest, "invalid_dpop_proof")
		return
	}

	if form.Get("requested_token_type") == TokenTypeUpstreamAccessToken && f.UpstreamDown {
		OAuthError(response, http.StatusServiceUnavailable, "temporarily_unavailable")
		return
	}

	if form.Get("requested_token_type") == TokenTypeUpstreamAccessToken {
		WriteJSON(response, http.StatusOK, map[string]any{
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

	access := f.AccessToken(id, scope, jkt)
	f.live[access] = liveToken{client: id, scope: scope, jkt: jkt}

	issued := TokenTypeAccessToken
	if f.IssuedAs != "" {
		issued = f.IssuedAs
	}

	body := map[string]any{
		"access_token":      access,
		"issued_token_type": issued,
		"token_type":        "Bearer",
		"expires_in":        300,
		"scope":             scope,
	}

	if jkt != "" {
		body["token_type"] = dpopHeader
	}

	WriteJSON(response, http.StatusOK, body)
}

func (f *Fake) introspect(response http.ResponseWriter, request *http.Request) {
	if err := request.ParseForm(); err != nil {
		OAuthError(response, http.StatusBadRequest, "invalid_request")
		return
	}

	id, _, ok := f.authenticated(request)
	if !ok {
		OAuthError(response, http.StatusUnauthorized, "invalid_client")
		return
	}

	f.lock.Lock()
	defer f.lock.Unlock()

	f.Seen[request.URL.Path] = request.PostForm
	held, known := f.live[request.PostForm.Get("token")]

	if !known || held.client != id {
		WriteJSON(response, http.StatusOK, map[string]any{"active": false, "scope": "leaked"})
		return
	}

	expiry := time.Now().Add(time.Hour)
	if f.StaleActive {
		expiry = time.Now().Add(-time.Hour)
	}

	body := map[string]any{
		"active":     true,
		"scope":      held.scope,
		"client_id":  held.client,
		"sub":        held.client,
		"aud":        []string{f.Audience},
		"iss":        f.URL(),
		"exp":        expiry.Unix(),
		"token_type": "Bearer",
		"org":        map[string]string{"id": "o-1", "key": "acme", "name": "Acme", "role": "owner"},
	}

	if held.jkt != "" {
		body["token_type"] = dpopHeader
		body["cnf"] = map[string]string{"jkt": held.jkt}
	}

	WriteJSON(response, http.StatusOK, body)
}

func (f *Fake) enroll(response http.ResponseWriter, request *http.Request) {
	if err := request.ParseForm(); err != nil {
		OAuthError(response, http.StatusBadRequest, "invalid_request")
		return
	}

	app, _, ok := f.authenticated(request)
	if !ok {
		OAuthError(response, http.StatusUnauthorized, "invalid_client")
		return
	}

	scope := request.PostForm.Get("scope")
	if scope == "" {
		OAuthError(response, http.StatusBadRequest, "invalid_request")
		return
	}

	token := rand.Text()
	machine := "machine-" + rand.Text()

	f.lock.Lock()
	f.Seen[request.URL.Path] = request.PostForm
	f.Initial[token] = machine
	f.EnrolledBy[machine] = app
	f.lock.Unlock()

	WriteJSON(response, http.StatusCreated, map[string]any{"initial_access_token": token, "expires_in": 900, "scope": scope})
}

func (f *Fake) unenroll(response http.ResponseWriter, request *http.Request) {
	body, err := io.ReadAll(request.Body)
	if err != nil {
		OAuthError(response, http.StatusBadRequest, "invalid_request")
		return
	}

	if request.PostForm, err = url.ParseQuery(string(body)); err != nil {
		OAuthError(response, http.StatusBadRequest, "invalid_request")
		return
	}

	app, _, ok := f.authenticated(request)
	if !ok {
		OAuthError(response, http.StatusUnauthorized, "invalid_client")
		return
	}

	machine := request.PathValue("machine")

	f.lock.Lock()
	defer f.lock.Unlock()

	if f.EnrolledBy[machine] != app {
		OAuthError(response, http.StatusNotFound, "invalid_request")
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

func (f *Fake) authorize(response http.ResponseWriter, request *http.Request) {
	query := request.URL.Query()

	f.lock.Lock()
	defer f.lock.Unlock()

	f.Asked = query
	client := f.clients[query.Get("client_id")]
	redirect := query.Get("redirect_uri")

	if client == nil || !slices.Contains(client.redirects, redirect) || query.Get("code_challenge_method") != "S256" {
		OAuthError(response, http.StatusBadRequest, "invalid_request")
		return
	}

	answer, _ := url.Parse(redirect)
	back := url.Values{"state": {query.Get("state")}, "iss": {f.URL()}}

	if f.Declined {
		back.Set("error", "access_denied")
		back.Set("error_description", "the person declined")
	} else {
		issued := rand.Text()
		back.Set("code", issued)
		f.codes[issued] = code{
			client: query.Get("client_id"), redirect: redirect, challenge: query.Get("code_challenge"),
			nonce: query.Get("nonce"), scope: query.Get("scope"), organization: query.Get("organization"),
			resource: query["resource"],
		}
	}

	answer.RawQuery = back.Encode()
	http.Redirect(response, request, answer.String(), http.StatusFound)
}

func (f *Fake) redeem(response http.ResponseWriter, request *http.Request, id string, client *Client, jkt string) {
	form := request.PostForm
	held, known := f.codes[form.Get("code")]
	delete(f.codes, form.Get("code"))

	sum := sha256.Sum256([]byte(form.Get("code_verifier")))

	if !known || held.client != id || held.redirect != form.Get("redirect_uri") ||
		base64.RawURLEncoding.EncodeToString(sum[:]) != held.challenge {
		OAuthError(response, http.StatusBadRequest, "invalid_grant")
		return
	}

	subject := f.Actor.Subject
	refresh := rand.Text()
	client.refresh[refresh] = true
	f.subjects[refresh] = subject

	access := f.accessTokenFor(subject, id, held.scope, jkt)
	f.live[access] = liveToken{client: id, subject: subject, scope: held.scope, jkt: jkt}

	body := map[string]any{
		"access_token":  access,
		"token_type":    "Bearer",
		"expires_in":    3600,
		"scope":         held.scope,
		"refresh_token": refresh,
	}

	if jkt != "" {
		body["token_type"] = dpopHeader
	}

	for scope := range strings.FieldsSeq(held.scope) {
		if provider, found := strings.CutPrefix(scope, ScopeDelegate); found && provider != "" {
			body["delegations"] = []map[string]string{{
				"connection": "connection-" + provider, "provider": provider, "provider_name": "Google", "subject": subject,
			}}
		}
	}

	if slices.Contains(strings.Fields(held.scope), ScopeOpenID) {
		claims := map[string]any{
			"iss": f.URL(), "sub": subject, "aud": id, "nonce": held.nonce, "sid": "sid-" + subject,
			"exp": time.Now().Add(15 * time.Minute).Unix(), "iat": time.Now().Unix(),
			"name": f.Actor.Name, "email": f.Actor.Email, "email_verified": true,
			"at_hash": accessTokenHash(access), "tenant": map[string]string{"uuid": "t-1", "subdomain": "acme", "name": "Acme"},
			"masks:avatars": map[string]any{"photo": nil, "identicon": f.URL() + "/avatars/" + subject + "/identicon"},
		}

		if f.AuthTime != 0 {
			claims["auth_time"] = f.AuthTime
		}

		if held.organization != "" {
			claims["org"] = map[string]string{"id": "o-" + held.organization, "key": held.organization, "name": "Acme", "role": f.Actor.Role}
		}

		body["id_token"] = f.Issue(claims, "JWT")
	}

	WriteJSON(response, http.StatusOK, body)
}

func (f *Fake) userinfo(response http.ResponseWriter, request *http.Request) {
	presented := strings.TrimPrefix(request.Header.Get("Authorization"), "Bearer ")

	f.lock.Lock()
	held, known := f.live[presented]
	name := f.Actor.Name
	if f.UserinfoName != "" {
		name = f.UserinfoName
	}
	role := f.Actor.Role
	f.lock.Unlock()

	if !known || held.subject == held.client {
		OAuthError(response, http.StatusUnauthorized, "invalid_token")
		return
	}

	WriteJSON(response, http.StatusOK, map[string]any{
		"sub":  held.subject,
		"name": name,
		"orgs": []map[string]string{
			{"id": "o-acme", "key": "acme", "name": "Acme", "role": role},
			{"id": "o-globex", "key": "globex", "name": "Globex", "role": "member"},
		},
	})
}

func (f *Fake) shake(response http.ResponseWriter, request *http.Request) {
	query := request.URL.Query()

	f.lock.Lock()
	f.Handshake = query
	declined := f.Declined
	f.lock.Unlock()

	answer, err := url.Parse(query.Get("return_to"))
	if err != nil || query.Get("resource") == "" {
		OAuthError(response, http.StatusBadRequest, "invalid_request")
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
		f.Initial[token] = id
		f.clients[id] = &Client{returnTo: query.Get("return_to"), postLogout: query.Get("post_logout_redirect_uri"), refresh: map[string]bool{}}
		f.lock.Unlock()

		back.Set("initial_access_token", token)
		back.Set("iss", f.URL())
	}

	answer.RawQuery = back.Encode()
	http.Redirect(response, request, answer.String(), http.StatusFound)
}

func (f *Fake) endSession(response http.ResponseWriter, request *http.Request) {
	query := request.URL.Query()

	f.lock.Lock()
	f.Ended = query
	client := f.clients[query.Get("client_id")]
	f.lock.Unlock()

	target := query.Get("post_logout_redirect_uri")
	if target == "" {
		WriteJSON(response, http.StatusOK, map[string]string{"signed_out": "true"})
		return
	}

	if client == nil || client.postLogout != target {
		OAuthError(response, http.StatusBadRequest, "invalid_request")
		return
	}

	answer, _ := url.Parse(target)
	back := answer.Query()
	back.Set("state", query.Get("state"))
	answer.RawQuery = back.Encode()

	http.Redirect(response, request, answer.String(), http.StatusFound)
}
