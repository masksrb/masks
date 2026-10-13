package web

import (
	"context"
	"crypto/rand"
	"crypto/subtle"
	"errors"
	"html/template"
	"io"
	"net/http"
	"net/url"
	"slices"
	"strconv"
	"strings"
	"time"

	masks "github.com/masksrb/masks/go"
)

const (
	avatarLimit = 5 << 20
)

var avatarSizes = []int{32, 64, 128, 256, 512}

func (a *App) routes() http.Handler {
	mux := http.NewServeMux()
	m := a.config.Mount

	mux.HandleFunc("GET "+m, a.start)
	mux.HandleFunc("GET "+m+"/{$}", a.start)
	mux.HandleFunc("GET "+m+"/callback", a.callback)
	mux.HandleFunc("GET "+m+"/session", a.describe)
	mux.HandleFunc("GET "+m+"/avatar", a.avatar)
	mux.HandleFunc("GET "+m+"/logout", a.guarded(a.logout))
	mux.HandleFunc("POST "+m+"/logout", a.guarded(a.logout))
	mux.HandleFunc("DELETE "+m+"/logout", a.guarded(a.logout))
	mux.HandleFunc("GET "+m+"/logout/return", a.farewell)
	mux.HandleFunc("POST "+m+"/logout/backchannel", a.backchannel)
	mux.HandleFunc("GET "+m+"/handshake", a.showHandshake)
	mux.HandleFunc("POST "+m+"/handshake", a.guarded(a.createHandshake))
	mux.HandleFunc("DELETE "+m+"/handshake", a.guarded(a.disconnect))
	mux.HandleFunc("POST "+m+"/handshake/disconnect", a.guarded(a.disconnect))
	mux.HandleFunc("GET "+m+"/handshake/callback", a.handshakeCallback)

	return mux
}

func (a *App) guarded(next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if !sameOrigin(r) {
			a.refuse(w, r, http.StatusForbidden, "invalid_request", "that request came from another site")
			return
		}

		next(w, r)
	}
}

type visit struct {
	site   *site
	state  *state
	person *Person
}

type visitKey struct{ app *App }

func (a *App) visiting(r *http.Request) (*visit, error) {
	if held, ok := r.Context().Value(visitKey{a}).(*visit); ok {
		return held, nil
	}

	s, err := a.site(r)
	if err != nil {
		return nil, err
	}

	held, err := a.load(r)
	if err != nil {
		return nil, err
	}

	return &visit{site: s, state: held}, nil
}

func (a *App) visit(w http.ResponseWriter, r *http.Request) (*visit, bool) {
	held, err := a.visiting(r)
	if err != nil {
		a.broken(w, r, err)
		return nil, false
	}

	return held, true
}

func (a *App) current(w http.ResponseWriter, r *http.Request) (*visit, *Person, bool) {
	held, ok := a.visit(w, r)
	if !ok {
		return nil, nil, false
	}

	person, err := a.signedIn(r, held)
	if err != nil {
		a.unavailable(w, r)
		return nil, nil, false
	}

	return held, person, true
}

func (a *App) within(ctx context.Context, held *visit, person *Person) context.Context {
	return WithPerson(context.WithValue(ctx, visitKey{a}, held), person)
}

func (a *App) signedIn(r *http.Request, v *visit) (*Person, error) {
	if v.person == nil {
		person, err := a.person(r, v.site, v.state)
		if err != nil {
			return nil, err
		}

		v.person = person
	}

	return v.person, nil
}

func (a *App) person(r *http.Request, s *site, held *state) (*Person, error) {
	nobody := PersonFrom(context.Background())
	data := held.data

	if s.held == nil || data.Token == nil {
		return nobody, nil
	}

	if data.Issuer != s.issuer.URL {
		held.forget()
		return nobody, nil
	}

	departed, err := a.departed(r.Context(), s.issuer.URL, data.Identity, data.SignedInAt)
	if err != nil {
		return nil, err
	}

	if departed {
		held.forget()
		return nobody, nil
	}

	if !data.Token.Valid() {
		if data.Token.RefreshToken == "" {
			held.forget()
			return nobody, nil
		}

		switch renewal := a.renew(r.Context(), s, data); renewal.Outcome {
		case renewed:
			changed := held.change()
			changed.Token, changed.Identity = renewal.Token, renewal.Identity
		case unregistered:
			_ = a.config.Credentials.Forget(r)
			held.forget()
			return nobody, nil
		case refused:
			held.forget()
			return nobody, nil
		default:
			return nobody, nil
		}
	}

	return a.personFrom(data.Identity, data.Token, s.issuer.URL+"/"), nil
}

func (a *App) broken(w http.ResponseWriter, r *http.Request, err error) {
	if errors.Is(err, ErrForeignCredentials) {
		a.refuse(w, r, http.StatusInternalServerError, "server_error", "the app's credentials were issued by another issuer")
		return
	}

	a.unavailable(w, r)
}

func (a *App) save(w http.ResponseWriter, r *http.Request, held *state) bool {
	if err := a.commit(w, r, held); err != nil {
		a.refuse(w, r, http.StatusInternalServerError, "server_error", "the session could not be saved")
		return false
	}

	return true
}

func (a *App) unavailable(w http.ResponseWriter, r *http.Request) {
	a.refuse(w, r, http.StatusServiceUnavailable, "temporarily_unavailable", "masks could not be reached")
}

func (a *App) start(w http.ResponseWriter, r *http.Request) {
	v, ok := a.visit(w, r)
	if !ok {
		return
	}

	s, held := v.site, v.state

	if s.held == nil {
		http.Redirect(w, r, a.HandshakePath(), http.StatusFound)
		return
	}

	if known, err := registered(r.Context(), s); err == nil && !known {
		_ = a.config.Credentials.Forget(r)
		http.Redirect(w, r, a.HandshakePath(), http.StatusFound)

		return
	}

	query := r.URL.Query()
	returnTo := localPath(query.Get("return_to"))

	if returnTo == "" {
		returnTo = held.data.ReturnTo
	}

	if held.data.ReturnTo != "" {
		held.change().ReturnTo = ""
	}

	organization := masks.OrganizationKey(query.Get("organization"))
	if organization == "" && a.config.Organization != nil {
		organization = masks.OrganizationKey(a.config.Organization(r))
	}

	started, err := a.signIn(s).AuthCodeURL(masks.AuthRequest{
		Scope:        a.scopeFor(query.Get("privilege")),
		Resource:     []string{s.resource},
		Organization: organization,
	})
	if err != nil {
		a.failed(w, r, err)
		return
	}

	held.open(started, returnTo)

	if !a.save(w, r, held) {
		return
	}

	http.Redirect(w, r, started.URL, http.StatusFound)
}

func (a *App) callback(w http.ResponseWriter, r *http.Request) {
	v, person, ok := a.current(w, r)
	if !ok {
		return
	}

	s, held := v.site, v.state

	query := r.URL.Query()
	pending := held.claim(query.Get("state"))

	if pending == nil || pending.Provider != "" {
		if code := query.Get("error"); code != "" {
			a.refuse(w, r, http.StatusBadRequest, code, query.Get("error_description"))
			return
		}

		a.stale(w, r, held, person)

		return
	}

	signed, err := a.signIn(s).Complete(r.Context(), query, &pending.Authorization)

	var refused *masks.Error

	switch {
	case errors.As(err, &refused) && refused.Code == "invalid_client":
		_ = a.config.Credentials.Forget(r)
		held.forget()

		if a.save(w, r, held) {
			http.Redirect(w, r, a.HandshakePath(), http.StatusFound)
		}

		return
	case err != nil:
		held.forget()

		if a.save(w, r, held) {
			a.failed(w, r, err)
		}

		return
	}

	identity := signed.Identity

	if profile, err := a.signIn(s).UserInfo(r.Context(), signed.Token); err == nil && profile.Subject == identity.Subject {
		if merged, err := profile.Merged(identity); err == nil {
			identity = merged
		}
	}

	if kept, err := identity.Kept(identityClaims...); err == nil {
		identity = kept
	}

	signed.Token.IDToken = ""

	held.renew(func(old *session) *session {
		return &session{
			Issuer:     s.issuer.URL,
			Token:      signed.Token,
			Identity:   identity,
			SignedInAt: time.Now().UnixMilli(),
			Requests:   old.Requests,
			Handshakes: old.Handshakes,
			SteppedUp:  old.SteppedUp,
		}
	})

	if !a.save(w, r, held) {
		return
	}

	target := pending.ReturnTo
	if target == "" {
		target = a.config.AfterSignIn
	}

	http.Redirect(w, r, target, http.StatusFound)
}

func (a *App) stale(w http.ResponseWriter, r *http.Request, held *state, person *Person) {
	if person.SignedIn {
		if a.save(w, r, held) {
			http.Redirect(w, r, a.config.AfterSignIn, http.StatusFound)
		}

		return
	}

	if !wantsJSON(r) && time.Now().Unix()-held.data.RestartedAt >= int64(restartWithin.Seconds()) {
		held.change().RestartedAt = time.Now().Unix()

		if a.save(w, r, held) {
			http.Redirect(w, r, a.config.Mount+"/", http.StatusFound)
		}

		return
	}

	if a.save(w, r, held) {
		a.refuse(w, r, http.StatusBadRequest, "invalid_state", "that sign-in request is not one this browser started, or it expired")
	}
}

func (a *App) describe(w http.ResponseWriter, r *http.Request) {
	v, person, ok := a.current(w, r)
	if !ok {
		return
	}

	s, held := v.site, v.state

	if !person.SignedIn {
		held.forget()

		if a.save(w, r, held) {
			writeJSON(w, http.StatusUnauthorized, a.refusal(r, s))
		}

		return
	}

	if a.save(w, r, held) {
		writeJSON(w, http.StatusOK, person)
	}
}

func (a *App) refusal(r *http.Request, s *site) map[string]any {
	if s == nil || s.held == nil {
		return map[string]any{"signed_in": false, "error": "handshake_required", "handshake_url": a.HandshakePath()}
	}

	return map[string]any{"signed_in": false, "error": "login_required", "login_url": a.LoginURL(LoginOptions{ReturnTo: referringPath(r)})}
}

func referringPath(r *http.Request) string {
	parsed, err := url.Parse(r.Referer())
	if err != nil || parsed.Host != r.Host {
		return ""
	}

	return localPath(parsed.RequestURI())
}

func (a *App) logout(w http.ResponseWriter, r *http.Request) {
	v, ok := a.visit(w, r)
	if !ok {
		return
	}

	s, held := v.site, v.state

	everywhere := a.config.SignOutOfIssuer || r.FormValue("everywhere") != ""
	upstream := ""
	farewell := ""

	if s.held != nil {
		client := a.signIn(s)

		if token := held.data.Token; token != nil && token.RefreshToken != "" {
			_ = client.Revoke(r.Context(), token.RefreshToken, masks.GrantRefreshToken)
		}

		if everywhere {
			farewell = rand.Text()
			upstream, _ = client.EndSessionURL(masks.EndSession{PostLogoutRedirectURI: a.farewellURI(s), State: farewell})
		}
	}

	held.renew(func(*session) *session {
		if upstream == "" {
			return &session{}
		}

		return &session{Farewell: farewell, FarewellUntil: time.Now().Add(pendingTTL).Unix()}
	})

	if !a.save(w, r, held) {
		return
	}

	if wantsJSON(r) {
		answer := map[string]any{"signed_in": false}
		if upstream != "" {
			answer["logout_url"] = upstream
		}

		writeJSON(w, http.StatusOK, answer)

		return
	}

	target := upstream
	if target == "" {
		target = a.config.AfterSignOut
	}

	http.Redirect(w, r, target, http.StatusFound)
}

func (a *App) farewell(w http.ResponseWriter, r *http.Request) {
	held, err := a.load(r)
	if err != nil {
		a.unavailable(w, r)
		return
	}

	expected, until := held.data.Farewell, held.data.FarewellUntil
	returned := r.URL.Query().Get("state")

	if expected != "" {
		changed := held.change()
		changed.Farewell, changed.FarewellUntil = "", 0
	}

	if !a.save(w, r, held) {
		return
	}

	if expected == "" || time.Now().Unix() > until || subtle.ConstantTimeCompare([]byte(expected), []byte(returned)) != 1 {
		a.refuse(w, r, http.StatusBadRequest, "invalid_state", "that sign-out is not one this browser started, or it expired")
		return
	}

	target := localPath(a.config.AfterSignOut)
	if target == "" {
		target = "/"
	}

	http.Redirect(w, r, target, http.StatusFound)
}

func (a *App) backchannel(w http.ResponseWriter, r *http.Request) {
	s, err := a.site(r)
	if err != nil {
		a.broken(w, r, err)
		return
	}

	r.Body = http.MaxBytesReader(w, r.Body, 64<<10)
	presented := r.PostFormValue("logout_token")

	if presented == "" || s.held == nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid_request", "error_description": "logout_token is required"})
		return
	}

	logout, err := a.signIn(s).VerifyLogoutToken(r.Context(), presented)
	if err != nil {
		var bad *masks.InvalidTokenError
		if errors.As(err, &bad) {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid_request", "error_description": bad.Description})
			return
		}

		a.unavailable(w, r)

		return
	}

	first, err := a.firstLogout(r.Context(), s.issuer.URL, logout)
	if err != nil {
		a.unavailable(w, r)
		return
	}

	if !first {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid_request", "error_description": "that logout token was already used"})
		return
	}

	if err := a.depart(r.Context(), s.issuer.URL, logout); err != nil {
		_ = a.config.Store.Delete(r.Context(), keyed("logout", s.issuer.URL, logout.ID))
		a.unavailable(w, r)

		return
	}

	if a.config.LoggedOut != nil {
		if err := a.config.LoggedOut(r, logout); err != nil {
			a.unavailable(w, r)
			return
		}
	}

	w.Header().Set("Cache-Control", "no-store")
	w.WriteHeader(http.StatusOK)
}

func (a *App) avatar(w http.ResponseWriter, r *http.Request) {
	v, person, ok := a.current(w, r)
	if !ok {
		return
	}

	s, held := v.site, v.state

	if !a.save(w, r, held) {
		return
	}

	photo := person.Avatars[masks.AvatarPhoto]

	if !person.SignedIn || photo == "" || !strings.HasPrefix(photo, s.issuer.URL+"/") {
		http.NotFound(w, r)
		return
	}

	if asked, err := strconv.Atoi(r.URL.Query().Get("size")); err == nil {
		size := avatarSizes[len(avatarSizes)-1]

		if found := slices.IndexFunc(avatarSizes, func(allowed int) bool { return allowed >= asked }); found >= 0 {
			size = avatarSizes[found]
		}

		photo += "?size=" + strconv.Itoa(size)
	}

	request, err := http.NewRequestWithContext(r.Context(), http.MethodGet, photo, nil)
	if err != nil {
		http.NotFound(w, r)
		return
	}

	request.Header.Set("Accept", "image/*")

	token := held.data.Token
	client := a.signIn(s).HTTPClient(masks.TokenSourceFunc(func(context.Context) (*masks.Token, error) { return token, nil }), s.issuer.URL)
	client.Timeout = 30 * time.Second
	client.CheckRedirect = func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse }

	response, err := client.Do(request)
	if err != nil {
		w.WriteHeader(http.StatusBadGateway)
		return
	}
	defer response.Body.Close()

	kind := response.Header.Get("Content-Type")

	switch {
	case response.StatusCode >= 300 && response.StatusCode < 400:
		location, err := response.Location()
		if err != nil || (location.Scheme != "https" && !strings.HasPrefix(location.String(), s.issuer.URL+"/")) {
			w.WriteHeader(http.StatusBadGateway)
			return
		}

		http.Redirect(w, r, location.String(), http.StatusFound)
	case response.StatusCode != http.StatusOK || !strings.HasPrefix(kind, "image/") || response.ContentLength > avatarLimit:
		http.NotFound(w, r)
	default:
		w.Header().Set("Content-Type", kind)
		w.Header().Set("Cache-Control", "private, max-age=300")
		w.Header().Set("X-Content-Type-Options", "nosniff")
		w.Header().Set("Content-Security-Policy", "default-src 'none'; style-src 'unsafe-inline'; sandbox")
		w.WriteHeader(http.StatusOK)
		_, _ = io.Copy(w, io.LimitReader(response.Body, avatarLimit))
	}
}

var connectedPage = template.Must(template.New("connected").Parse(`<!doctype html>
<meta charset="utf-8">
<title>{{.Name}} and masks</title>
<p>{{.Name}} is connected to {{.Issuer}} as {{.ClientID}}.</p>
<form method="post" action="{{.Handshake}}"><button>Connect again</button></form>
<form method="post" action="{{.Handshake}}/disconnect"><button>Disconnect</button></form>
`))

func (a *App) mayManage(w http.ResponseWriter, r *http.Request, v *visit) bool {
	person, err := a.signedIn(r, v)
	if err != nil {
		a.unavailable(w, r)
		return false
	}

	if person.SignedIn && a.config.Manages != nil && a.config.Manages(r, person) {
		return true
	}

	if !a.save(w, r, v.state) {
		return false
	}

	switch {
	case person.SignedIn:
		a.refuse(w, r, http.StatusForbidden, "forbidden", "only somebody this app lets manage its connection can reconnect or disconnect it")
	case wantsJSON(r):
		writeJSON(w, http.StatusUnauthorized, a.refusal(r, v.site))
	default:
		http.Redirect(w, r, a.config.AfterSignOut, http.StatusFound)
	}

	return false
}

func (a *App) showHandshake(w http.ResponseWriter, r *http.Request) {
	v, ok := a.visit(w, r)
	if !ok {
		return
	}

	s := v.site

	if s.held == nil {
		a.shake(w, r, v)
		return
	}

	if !a.mayManage(w, r, v) || !a.save(w, r, v.state) {
		return
	}

	if wantsJSON(r) {
		writeJSON(w, http.StatusOK, map[string]any{"connected": true, "issuer": s.issuer.URL, "client_id": s.held.ClientID})
		return
	}

	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	w.Header().Set("Cache-Control", "no-store")
	_ = connectedPage.Execute(w, map[string]string{
		"Name": a.handshake(s).Name, "Issuer": s.issuer.URL, "ClientID": s.held.ClientID, "Handshake": a.HandshakePath(),
	})
}

func (a *App) createHandshake(w http.ResponseWriter, r *http.Request) {
	v, ok := a.visit(w, r)
	if !ok {
		return
	}

	if v.site.held != nil && !a.mayManage(w, r, v) {
		return
	}

	a.shake(w, r, v)
}

func (a *App) shake(w http.ResponseWriter, r *http.Request, v *visit) {
	target, shaken, err := a.handshake(v.site).Start()
	if err != nil {
		a.failed(w, r, err)
		return
	}

	v.state.shake(shaken)

	if a.save(w, r, v.state) {
		http.Redirect(w, r, target, http.StatusFound)
	}
}

func (a *App) handshakeCallback(w http.ResponseWriter, r *http.Request) {
	v, ok := a.visit(w, r)
	if !ok {
		return
	}

	s, held := v.site, v.state
	query := r.URL.Query()
	returned := query.Get("state")

	if !held.shaken(returned) {
		if a.save(w, r, held) {
			a.refuse(w, r, http.StatusBadRequest, "invalid_state", "that connection request is not one this browser started, or it expired")
		}

		return
	}

	if s.held != nil && !a.mayManage(w, r, v) {
		return
	}

	if writable, ok := a.config.Credentials.(WritableStore); ok {
		if err := writable.Writable(r); err != nil {
			a.save(w, r, held)
			a.refuse(w, r, http.StatusInternalServerError, "server_error", "the credentials could not be saved, so the app did not connect")

			return
		}
	}

	registration, err := a.handshake(s).Complete(r.Context(), query, returned)
	if err != nil {
		if a.save(w, r, held) {
			a.failed(w, r, err)
		}

		return
	}

	if err := a.config.Credentials.Save(r, CredentialsFrom(s.issuer.URL, registration)); err != nil {
		_ = s.issuer.DeleteRegistration(r.Context(), registration)
		a.save(w, r, held)
		a.refuse(w, r, http.StatusInternalServerError, "server_error", "the credentials could not be saved, so the app did not connect")

		return
	}

	held.forget()

	if a.save(w, r, held) {
		http.Redirect(w, r, a.config.Mount+"/", http.StatusFound)
	}
}

func (a *App) disconnect(w http.ResponseWriter, r *http.Request) {
	v, ok := a.visit(w, r)
	if !ok {
		return
	}

	s, held := v.site, v.state

	if s.held == nil {
		http.Redirect(w, r, a.HandshakePath(), http.StatusFound)
		return
	}

	if !a.mayManage(w, r, v) {
		return
	}

	if s.held.RegistrationAccessToken != "" && s.held.RegistrationClientURI != "" {
		err := s.issuer.DeleteRegistration(r.Context(), s.held.Registration())

		var refused *masks.Error
		if err != nil && !(errors.As(err, &refused) && refused.Status < 500) {
			a.failed(w, r, err)
			return
		}
	}

	if err := a.config.Credentials.Forget(r); err != nil {
		a.refuse(w, r, http.StatusInternalServerError, "server_error", "the credentials could not be removed")
		return
	}

	held.renew(func(*session) *session { return &session{} })

	if a.save(w, r, held) {
		http.Redirect(w, r, a.HandshakePath(), http.StatusFound)
	}
}
