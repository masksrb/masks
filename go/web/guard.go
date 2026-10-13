package web

import (
	"encoding/json"
	"errors"
	"net/http"
	"slices"
	"strings"
	"time"

	masks "github.com/masksrb/masks/go"
)

func (a *App) Session(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		v, person, ok := a.current(w, r)
		if !ok || !a.save(w, r, v.state) {
			return
		}

		next.ServeHTTP(w, r.WithContext(a.within(r.Context(), v, person)))
	})
}

func (a *App) Require(privileges ...string) func(http.Handler) http.Handler {
	wanted := a.mustPrivileges(privileges)

	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			if v, ok := a.visit(w, r); ok {
				a.requireSession(w, r, v, next, privileges, wanted)
			}
		})
	}
}

func (a *App) requireSession(w http.ResponseWriter, r *http.Request, v *visit, next http.Handler, names []string, wanted []Privilege) {
	person, err := a.signedIn(r, v)
	if err != nil {
		a.unavailable(w, r)
		return
	}

	held := v.state

	if !person.SignedIn {
		a.signInFirst(w, r, v.site, held)
		return
	}

	for _, privilege := range wanted {
		if refused := person.refused(privilege); refused != nil {
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

	next.ServeHTTP(w, r.WithContext(a.within(r.Context(), v, person)))
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
			a.forbid(w, r, &Forbidden{
				Code:        "insufficient_scope",
				Description: "this account does not hold the " + strings.Join(missing, " and ") + " privilege",
				Scope:       strings.Join(scopes, " "),
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

func (a *App) forbid(w http.ResponseWriter, r *http.Request, refused *Forbidden) {
	a.refuse(w, r, http.StatusForbidden, refused.Code, refused.Description)
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

			v, ok := a.visit(w, r)
			if !ok {
				return
			}

			if v.state.data.Token == nil {
				a.requireToken(w, r, next, wanted)
				return
			}

			a.requireSession(w, r, v, next, privileges, wanted)
		})
	}
}

func (a *App) verifier(r *http.Request) (*masks.Verifier, error) {
	issuer, err := a.issuerFor(r)
	if err != nil {
		return nil, err
	}

	resource, origin, err := a.resourceFor(r)
	if err != nil {
		return nil, err
	}

	metadata, err := masks.ResourceMetadataURL(resource)
	if err != nil {
		return nil, err
	}

	key := issuer.URL + " " + resource

	a.lock.Lock()
	defer a.lock.Unlock()

	held := a.verifiers[key]
	if held == nil || held.Issuer != issuer {
		if held == nil && len(a.verifiers) >= remembered {
			for name := range a.verifiers {
				delete(a.verifiers, name)
				break
			}
		}

		held = masks.NewVerifier(issuer, resource)
		held.PublicURL = origin
		held.Replay = a.replay()
		held.ResourceMetadata = metadata
		a.verifiers[key] = held
	}

	return held, nil
}

func (a *App) requireToken(w http.ResponseWriter, r *http.Request, next http.Handler, wanted []Privilege) {
	verifier, err := a.verifier(r)
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

		a.challenge(w, verifier, http.StatusUnauthorized, &Forbidden{Code: "invalid_token", Description: bad.Description})

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
		a.challenge(w, verifier, http.StatusForbidden, &Forbidden{
			Code: "insufficient_scope", Description: "this token does not carry " + strings.Join(scopes, " "), Scope: strings.Join(scopes, " "),
		})

		return
	}

	for _, privilege := range wanted {
		if refused := person.refused(privilege); refused != nil {
			a.challenge(w, verifier, http.StatusForbidden, refused)
			return
		}
	}

	next.ServeHTTP(w, r.WithContext(WithPerson(r.Context(), person)))
}

func presentedToken(r *http.Request) string {
	_, token, _ := strings.Cut(r.Header.Get("Authorization"), " ")

	return strings.TrimSpace(token)
}

func (a *App) challenge(w http.ResponseWriter, verifier *masks.Verifier, status int, refused *Forbidden) {
	scope := refused.Scope
	if scope == "" && len(a.config.ResourceScopes) > 0 {
		scope = strings.Join(a.config.ResourceScopes, " ")
	}

	for _, challenge := range verifier.Challenge(refused.Code, refused.Description, scope) {
		w.Header().Add("WWW-Authenticate", challenge)
	}

	writeJSON(w, status, map[string]string{"error": refused.Code, "error_description": refused.Description})
}

func (a *App) ResourceMetadata() http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		verifier, err := a.verifier(r)
		if err != nil {
			a.unavailable(w, r)
			return
		}

		body := map[string]any{
			"resource":                          verifier.Audience[0],
			"authorization_servers":             []string{verifier.Issuer.URL},
			"bearer_methods_supported":          []string{"header"},
			"dpop_signing_alg_values_supported": masks.ProofAlgorithms(),
		}

		if len(a.config.ResourceScopes) > 0 {
			body["scopes_supported"] = a.config.ResourceScopes
		}

		if name := a.nameFor(r); name != "" {
			body["resource_name"] = name
		}

		w.Header().Set("Content-Type", "application/json")
		w.Header().Set("Cache-Control", "public, max-age=300")
		writeMetadata(w, body)
	})
}

func (a *App) delegations(r *http.Request) (*visit, *masks.Client, error) {
	if !a.config.Delegates {
		return nil, nil, errors.New("masks/web: Config.Delegates is off")
	}

	v, err := a.visiting(r)
	if err != nil {
		return nil, nil, err
	}

	if v.site.held == nil {
		return nil, nil, ErrNotConnected
	}

	return v, v.site.client(a.delegationURI(v.site)), nil
}

func (a *App) Delegations(r *http.Request) (*masks.Client, error) {
	_, client, err := a.delegations(r)

	return client, err
}

func (a *App) StartDelegation(w http.ResponseWriter, r *http.Request, provider string, asked masks.AuthRequest) error {
	v, client, err := a.delegations(r)
	if err != nil {
		return err
	}

	held := v.state

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
	v, client, err := a.delegations(r)
	if err != nil {
		return nil, err
	}

	held := v.state

	person, err := a.signedIn(r, v)
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
