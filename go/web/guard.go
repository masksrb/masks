package web

import (
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"net/url"
	"slices"
	"strings"
	"time"

	masks "github.com/masksrb/masks/go"
)

const resourcePath = "/.well-known/oauth-protected-resource"

func (a *App) Session(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		_, held, person, err := a.current(r)
		if err != nil {
			a.unavailable(w, r)
			return
		}

		if !a.save(w, r, held) {
			return
		}

		next.ServeHTTP(w, r.WithContext(WithPerson(r.Context(), person)))
	})
}

func (a *App) Require(privileges ...string) func(http.Handler) http.Handler {
	wanted := a.mustPrivileges(privileges)

	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			a.requireSession(w, r, next, privileges, wanted)
		})
	}
}

func (a *App) requireSession(w http.ResponseWriter, r *http.Request, next http.Handler, names []string, wanted []Privilege) {
	s, err := a.site(r)
	if err != nil {
		a.unavailable(w, r)
		return
	}

	held, err := a.load(r)
	if err != nil {
		a.unavailable(w, r)
		return
	}

	person, err := a.signedIn(r, s, held)
	if err != nil {
		a.unavailable(w, r)
		return
	}

	if !person.SignedIn {
		a.signInFirst(w, r, s, held)
		return
	}

	for _, privilege := range wanted {
		if refused := person.member(privilege); refused != nil {
			if a.save(w, r, held) {
				a.forbid(w, r, refused)
			}

			return
		}
	}

	var missing []string

	for index, privilege := range wanted {
		for _, scope := range privilege.Scope {
			if !slices.Contains(person.Scopes, scope) && !slices.Contains(missing, names[index]) {
				missing = append(missing, names[index])
			}
		}
	}

	if len(missing) > 0 {
		a.askAgain(w, r, held, missing)
		return
	}

	if held.data.SteppedUp != nil {
		held.change().SteppedUp = nil
	}

	if !a.save(w, r, held) {
		return
	}

	next.ServeHTTP(w, r.WithContext(WithPerson(r.Context(), person)))
}

func (a *App) signInFirst(w http.ResponseWriter, r *http.Request, s *site, held *state) {
	if wantsJSON(r) {
		if a.save(w, r, held) {
			writeJSON(w, http.StatusUnauthorized, a.refusal(r, s))
		}

		return
	}

	if s.held == nil {
		if a.save(w, r, held) {
			http.Redirect(w, r, a.HandshakePath(), http.StatusFound)
		}

		return
	}

	if r.Method == http.MethodGet {
		held.change().ReturnTo = localPath(r.URL.RequestURI())
	}

	if a.save(w, r, held) {
		http.Redirect(w, r, a.config.Mount+"/", http.StatusFound)
	}
}

func (a *App) askAgain(w http.ResponseWriter, r *http.Request, held *state, missing []string) {
	asked := held.data.SteppedUp
	changed := held.change()
	changed.SteppedUp = nil

	if asked != nil && time.Since(time.Unix(asked.At, 0)) < stepUpWithin && !slices.ContainsFunc(missing, func(name string) bool {
		return !slices.Contains(asked.Privileges, name)
	}) {
		var scopes []string

		for _, name := range missing {
			scopes = append(scopes, a.config.Privileges[name].Scope...)
		}

		if a.save(w, r, held) {
			a.forbid(w, r, &refusal{
				code:        "insufficient_scope",
				description: "this account does not hold the " + strings.Join(missing, " and ") + " privilege",
				scope:       strings.Join(scopes, " "),
			})
		}

		return
	}

	returnTo := referringPath(r)
	if r.Method == http.MethodGet {
		returnTo = localPath(r.URL.RequestURI())
	}

	target := a.LoginURL(LoginOptions{ReturnTo: returnTo, Privileges: missing})
	changed.SteppedUp = &steppedUp{Privileges: missing, At: time.Now().Unix()}

	if !a.save(w, r, held) {
		return
	}

	if wantsJSON(r) {
		writeJSON(w, http.StatusForbidden, map[string]any{"error": "privilege_required", "privileges": missing, "login_url": target})
		return
	}

	http.Redirect(w, r, target, http.StatusFound)
}

func (a *App) forbid(w http.ResponseWriter, r *http.Request, refused *refusal) {
	a.refuse(w, r, http.StatusForbidden, refused.code, refused.description)
}

func (a *App) Protect(privileges ...string) func(http.Handler) http.Handler {
	wanted := a.mustPrivileges(privileges)

	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			a.requireToken(w, r, next, wanted)
		})
	}
}

func (a *App) Either(privileges ...string) func(http.Handler) http.Handler {
	wanted := a.mustPrivileges(privileges)

	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			if r.Header.Get("Authorization") != "" {
				a.requireToken(w, r, next, wanted)
				return
			}

			held, err := a.load(r)
			if err != nil {
				a.unavailable(w, r)
				return
			}

			if held.data.Token == nil {
				a.requireToken(w, r, next, wanted)
				return
			}

			a.requireSession(w, r, next, privileges, wanted)
		})
	}
}

func (a *App) verifier(r *http.Request) (*masks.Verifier, string, error) {
	issuer, err := a.issuerFor(r)
	if err != nil {
		return nil, "", err
	}

	resource := a.config.Resource
	if a.config.ResourceFor != nil {
		if resource, err = a.config.ResourceFor(r); err != nil {
			return nil, "", err
		}
	}

	parsed, err := url.Parse(resource)
	if err != nil || parsed.Host == "" {
		return nil, "", fmt.Errorf("masks/web: %q is not an absolute resource URL", resource)
	}

	key := issuer.URL + " " + resource

	a.lock.Lock()
	defer a.lock.Unlock()

	held := a.verifiers[key]
	if held == nil || held.Issuer != issuer {
		held = masks.NewVerifier(issuer, resource)
		held.PublicURL = parsed.Scheme + "://" + parsed.Host
		held.Replay = a.replay()
		a.verifiers[key] = held
	}

	return held, resource, nil
}

func (a *App) requireToken(w http.ResponseWriter, r *http.Request, next http.Handler, wanted []Privilege) {
	verifier, resource, err := a.verifier(r)
	if err != nil {
		a.unavailable(w, r)
		return
	}

	claims, err := verifier.Authenticate(r)
	if err != nil {
		var bad *masks.InvalidTokenError
		if !errors.As(err, &bad) {
			writeJSON(w, http.StatusServiceUnavailable, map[string]string{"error": "temporarily_unavailable", "error_description": "the token could not be checked"})
			return
		}

		a.challenge(w, resource, http.StatusUnauthorized, &refusal{code: "invalid_token", description: bad.Description})

		return
	}

	person := a.personFromClaims(claims, presentedToken(r))
	var scopes []string

	for _, privilege := range wanted {
		for _, scope := range privilege.Scope {
			if !claims.HasScope(scope) && !slices.Contains(scopes, scope) {
				scopes = append(scopes, scope)
			}
		}
	}

	if len(scopes) > 0 {
		a.challenge(w, resource, http.StatusForbidden, &refusal{
			code: "insufficient_scope", description: "this token does not carry " + strings.Join(scopes, " "), scope: strings.Join(scopes, " "),
		})

		return
	}

	for _, privilege := range wanted {
		if refused := person.member(privilege); refused != nil {
			a.challenge(w, resource, http.StatusForbidden, refused)
			return
		}
	}

	next.ServeHTTP(w, r.WithContext(WithPerson(r.Context(), person)))
}

func presentedToken(r *http.Request) string {
	_, token, _ := strings.Cut(r.Header.Get("Authorization"), " ")

	return strings.TrimSpace(token)
}

func metadataURL(resource string) string {
	parsed, err := url.Parse(resource)
	if err != nil {
		return ""
	}

	path := strings.TrimSuffix(parsed.EscapedPath(), "/")

	return parsed.Scheme + "://" + parsed.Host + resourcePath + path
}

func quoted(value string) string {
	return strings.Map(func(r rune) rune {
		if r == '"' || r == '\\' || r < 0x20 || r == 0x7f {
			return ' '
		}

		return r
	}, value)
}

func (a *App) challenge(w http.ResponseWriter, resource string, status int, refused *refusal) {
	scope := refused.scope
	if scope == "" && len(a.config.ResourceScopes) > 0 {
		scope = strings.Join(a.config.ResourceScopes, " ")
	}

	parameters := fmt.Sprintf(`error="%s", error_description="%s"`, quoted(refused.code), quoted(refused.description))

	if scope != "" {
		parameters += fmt.Sprintf(`, scope="%s"`, quoted(scope))
	}

	parameters += fmt.Sprintf(`, resource_metadata="%s"`, quoted(metadataURL(resource)))

	w.Header().Add("WWW-Authenticate", "Bearer "+parameters)
	w.Header().Add("WWW-Authenticate", masks.DPoP+` algs="ES256 ES384 ES512 PS256 PS384 PS512 RS256", `+parameters)

	writeJSON(w, status, map[string]string{"error": refused.code, "error_description": refused.description})
}

func (a *App) ResourceMetadata() http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		verifier, resource, err := a.verifier(r)
		if err != nil {
			a.unavailable(w, r)
			return
		}

		body := map[string]any{
			"resource":                          resource,
			"authorization_servers":             []string{verifier.Issuer.URL},
			"bearer_methods_supported":          []string{"header"},
			"dpop_signing_alg_values_supported": []string{"ES256", "ES384", "ES512", "PS256", "PS384", "PS512", "RS256"},
		}

		if len(a.config.ResourceScopes) > 0 {
			body["scopes_supported"] = a.config.ResourceScopes
		}

		if a.config.Name != "" {
			body["resource_name"] = a.config.Name
		}

		w.Header().Set("Content-Type", "application/json")
		w.Header().Set("Cache-Control", "public, max-age=300")
		writeMetadata(w, body)
	})
}

func (a *App) MetadataPath(r *http.Request) (string, error) {
	_, resource, err := a.verifier(r)
	if err != nil {
		return "", err
	}

	parsed, err := url.Parse(metadataURL(resource))
	if err != nil {
		return "", err
	}

	return parsed.Path, nil
}

func (a *App) delegations(r *http.Request) (*site, *masks.Client, error) {
	if !a.config.Delegates {
		return nil, nil, errors.New("masks/web: Config.Delegates is off")
	}

	s, err := a.site(r)
	if err != nil {
		return nil, nil, err
	}

	if s.held == nil {
		return nil, nil, ErrNotConnected
	}

	return s, s.client(s.origin + localPath(a.config.DelegationPath)), nil
}

func (a *App) Delegations(r *http.Request) (*masks.Client, error) {
	_, client, err := a.delegations(r)

	return client, err
}

func (a *App) StartDelegation(w http.ResponseWriter, r *http.Request, provider string, asked masks.AuthRequest) error {
	_, client, err := a.delegations(r)
	if err != nil {
		return err
	}

	held, err := a.load(r)
	if err != nil {
		return err
	}

	started, err := client.StartDelegation(provider, asked)
	if err != nil {
		return err
	}

	held.open(started, "")

	if err := a.commit(w, r, held); err != nil {
		return err
	}

	http.Redirect(w, r, started.URL, http.StatusFound)

	return nil
}

func (a *App) FinishDelegation(w http.ResponseWriter, r *http.Request) (*masks.Connected, error) {
	s, client, err := a.delegations(r)
	if err != nil {
		return nil, err
	}

	held, err := a.load(r)
	if err != nil {
		return nil, err
	}

	person, err := a.signedIn(r, s, held)
	if err != nil {
		return nil, err
	}

	pending := held.claim(r.URL.Query().Get("state"))

	if err := a.commit(w, r, held); err != nil {
		return nil, err
	}

	if pending == nil || pending.Provider == "" {
		return nil, &masks.DelegationError{Code: "invalid_state", Description: "that connection is not one this browser started, or it expired"}
	}

	connected, err := client.FinishDelegation(r.Context(), r.URL.Query(), &pending.Authorization)
	if err != nil {
		return nil, err
	}

	if person.SignedIn && connected.Subject != "" && connected.Subject != person.Subject {
		return nil, &masks.DelegationError{Code: "access_denied", Description: "someone other than the person signed in finished that connection"}
	}

	return connected, nil
}

func writeMetadata(w http.ResponseWriter, body map[string]any) {
	w.WriteHeader(http.StatusOK)
	_ = json.NewEncoder(w).Encode(body)
}
