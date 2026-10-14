package web

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"maps"
	"mime"
	"net/http"
	"net/url"
	"slices"
	"strings"
	"sync"
	"time"

	masks "github.com/masksrb/masks/go"
)

const (
	discoveryLifetime = time.Hour
	discoveryTimeout  = 30 * time.Second
	firstBackoff      = 5 * time.Second
	longestBackoff    = time.Minute
	remembered        = 1000
)

type Privilege struct {
	Scope        []string
	Role         []string
	Organization string
}

type Config struct {
	Issuer      string
	IssuerFor   func(*http.Request) (string, error)
	Resource    string
	ResourceFor func(*http.Request) (string, error)
	Name        string
	NameFor     func(*http.Request) string

	Scope          []string
	Namespace      string
	ResourceScopes []string
	Privileges     map[string]Privilege
	Organization   func(*http.Request) string

	Mount           string
	AfterSignIn     string
	AfterSignOut    string
	SignOutOfIssuer bool

	Secret          []byte
	PreviousSecrets [][]byte
	Sessions        Store
	SessionLifetime time.Duration
	PlainHTTP       bool

	Credentials CredentialStore
	Manages     func(*http.Request, *Actor) bool
	LoggedOut   func(*http.Request, *masks.LogoutToken) error
	Store       Store

	Delegates      bool
	DelegationPath string

	HTTPClient *http.Client
	Options    []masks.Option
}

type App struct {
	config  Config
	sealer  *sealer
	names   []string
	handler http.Handler

	lock      sync.Mutex
	issuers   map[string]*discovered
	verifiers map[string]*masks.Verifier

	flights flights
}

type discovered struct {
	issuer  *masks.Issuer
	at      time.Time
	used    time.Time
	failure error
	retry   time.Time
	backoff time.Duration
	pending chan struct{}
}

type site struct {
	issuer   *masks.Issuer
	resource string
	origin   string
	held     *Credentials
}

func New(config Config) (*App, error) {
	if config.Issuer == "" && config.IssuerFor == nil {
		return nil, errors.New("masks/web: Config.Issuer or Config.IssuerFor names the issuer")
	}

	if config.Resource == "" && config.ResourceFor == nil {
		return nil, errors.New("masks/web: Config.Resource or Config.ResourceFor names this app's resource URL")
	}

	if len(config.Scope) == 0 {
		config.Scope = append([]string{}, masks.DefaultScope...)
	}

	if !slices.Contains(config.Scope, masks.ScopeOpenID) {
		return nil, errors.New("masks/web: Config.Scope includes openid, since a sign-in is an ID token")
	}

	config.Mount = "/" + strings.Trim(config.Mount, "/")
	if config.Mount == "/" {
		config.Mount = "/auth"
	}

	if config.AfterSignIn == "" {
		config.AfterSignIn = "/"
	}

	if config.AfterSignOut == "" {
		config.AfterSignOut = "/"
	}

	if config.SessionLifetime <= 0 {
		config.SessionLifetime = 14 * 24 * time.Hour
	}

	if config.Credentials == nil && config.IssuerFor != nil {
		return nil, errors.New("masks/web: Config.IssuerFor needs Credentials that keep each issuer's credentials apart")
	}

	if config.Credentials == nil {
		config.Credentials = FileCredentials("masks.json")
	}

	if config.Store == nil {
		config.Store = &MemoryStore{}
	}

	if config.Delegates && localPath(config.DelegationPath) == "" {
		return nil, errors.New("masks/web: Config.Delegates needs a DelegationPath on this app, such as /connect/callback")
	}

	if config.HTTPClient != nil {
		config.Options = append([]masks.Option{masks.WithHTTPClient(config.HTTPClient)}, config.Options...)
	}

	if config.PlainHTTP {
		config.Options = append(config.Options, masks.AllowPlainHTTP())
	}

	config.Privileges = maps.Clone(config.Privileges)

	for name, privilege := range config.Privileges {
		if name == "" || strings.ContainsAny(name, " \t") {
			return nil, fmt.Errorf("masks/web: %q is not a privilege name", name)
		}

		if len(privilege.Scope) == 0 && len(privilege.Role) == 0 && privilege.Organization == "" {
			return nil, fmt.Errorf("masks/web: the %s privilege asks for nothing", name)
		}
	}

	sealer, err := newSealer(config.Secret, config.PreviousSecrets)
	if err != nil {
		return nil, err
	}

	app := &App{
		config:    config,
		sealer:    sealer,
		names:     slices.Sorted(maps.Keys(config.Privileges)),
		issuers:   map[string]*discovered{},
		verifiers: map[string]*masks.Verifier{},
	}

	app.handler = app.routes()

	return app, nil
}

func (a *App) issuerFor(r *http.Request) (*masks.Issuer, error) {
	named := a.config.Issuer

	if a.config.IssuerFor != nil {
		var err error
		if named, err = a.config.IssuerFor(r); err != nil {
			return nil, err
		}
	}

	named = strings.TrimSuffix(named, "/")
	now := time.Now()

	a.lock.Lock()
	held := a.issuers[named]

	if held == nil {
		held = &discovered{backoff: firstBackoff}
		a.rememberIssuer(named, held)
	}

	held.used = now
	stale := held.issuer == nil || now.Sub(held.at) >= discoveryLifetime

	if stale && held.pending == nil && !now.Before(held.retry) {
		held.pending = make(chan struct{})
		go a.discover(named, held)
	}

	found, pending, failure := held.issuer, held.pending, held.failure
	a.lock.Unlock()

	if found != nil {
		return found, nil
	}

	if pending == nil {
		return nil, failure
	}

	select {
	case <-pending:
	case <-r.Context().Done():
		return nil, r.Context().Err()
	}

	a.lock.Lock()
	defer a.lock.Unlock()

	if held.issuer != nil {
		return held.issuer, nil
	}

	return nil, held.failure
}

func (a *App) discover(named string, held *discovered) {
	ctx, cancel := context.WithTimeout(context.Background(), discoveryTimeout)
	defer cancel()

	found, err := masks.Discover(ctx, named, a.config.Options...)

	a.lock.Lock()
	defer a.lock.Unlock()

	if err != nil {
		held.failure = err
		held.retry = time.Now().Add(held.backoff)
		held.backoff = min(2*held.backoff, longestBackoff)
	} else {
		held.issuer, held.at, held.failure, held.retry, held.backoff = found, time.Now(), nil, time.Time{}, firstBackoff
	}

	close(held.pending)
	held.pending = nil
}

func (a *App) rememberIssuer(named string, held *discovered) {
	if len(a.issuers) >= remembered {
		oldest := ""

		for name, entry := range a.issuers {
			if oldest == "" || entry.used.Before(a.issuers[oldest].used) {
				oldest = name
			}
		}

		delete(a.issuers, oldest)
	}

	a.issuers[named] = held
}

func (a *App) resourceFor(r *http.Request) (string, string, error) {
	resource := a.config.Resource

	if a.config.ResourceFor != nil {
		var err error
		if resource, err = a.config.ResourceFor(r); err != nil {
			return "", "", err
		}
	}

	parsed, err := url.Parse(resource)
	if err != nil || parsed.Host == "" || (parsed.Scheme != "https" && !(a.config.PlainHTTP && parsed.Scheme == "http")) {
		return "", "", fmt.Errorf("masks/web: %q is not an absolute https resource URL", resource)
	}

	return resource, parsed.Scheme + "://" + parsed.Host, nil
}

func (a *App) site(r *http.Request) (*site, error) {
	issuer, err := a.issuerFor(r)
	if err != nil {
		return nil, err
	}

	resource, origin, err := a.resourceFor(r)
	if err != nil {
		return nil, err
	}

	held, err := a.config.Credentials.Load(r)
	if err != nil {
		return nil, err
	}

	if held != nil && held.Issuer != issuer.URL && (held.Issuer != "" || a.config.IssuerFor != nil) {
		return nil, ErrForeignCredentials
	}

	return &site{issuer: issuer, resource: resource, origin: origin, held: held}, nil
}

func (s *site) client(redirect string) *masks.Client {
	if s.held == nil {
		return &masks.Client{Issuer: s.issuer}
	}

	client := s.issuer.Client(s.held.Registration(), nil, nil)
	client.RedirectURI = redirect

	return client
}

func (a *App) signIn(s *site) *masks.Client {
	return s.client(a.callbackURI(s))
}

func (a *App) callbackURI(s *site) string {
	return s.origin + a.config.Mount + "/callback"
}

func (a *App) delegationURI(s *site) string {
	return s.origin + localPath(a.config.DelegationPath)
}

func (a *App) farewellURI(s *site) string {
	return s.origin + a.config.Mount + "/logout/return"
}

func (a *App) returnTo(s *site) string {
	return s.origin + a.config.Mount + "/handshake/callback"
}

func withScopes(base []string, privileges ...Privilege) []string {
	asked := slices.Clone(base)

	for _, privilege := range privileges {
		for _, scope := range privilege.Scope {
			if !slices.Contains(asked, scope) {
				asked = append(asked, scope)
			}
		}
	}

	return asked
}

func (a *App) approvedScope() []string {
	asked := withScopes(a.config.Scope, a.mustPrivileges(a.names)...)

	if a.config.Namespace != "" {
		asked = slices.DeleteFunc(asked, func(scope string) bool { return strings.HasPrefix(scope, a.config.Namespace) })
		asked = append(asked, a.config.Namespace)
	}

	if a.config.Delegates {
		asked = append(asked, masks.ScopeDelegate)
	}

	return asked
}

func (a *App) nameFor(r *http.Request) string {
	if a.config.NameFor != nil {
		return a.config.NameFor(r)
	}

	return a.config.Name
}

func (a *App) handshake(r *http.Request, s *site) *masks.Handshake {
	name := a.nameFor(r)
	if name == "" {
		name = strings.TrimPrefix(strings.TrimPrefix(s.origin, "https://"), "http://")
	}

	redirects := []string{a.callbackURI(s)}

	if a.config.Delegates {
		redirects = append(redirects, a.delegationURI(s))
	}

	return &masks.Handshake{
		Issuer:                s.issuer,
		Name:                  name,
		Resource:              s.resource,
		RedirectURIs:          redirects,
		ReturnTo:              a.returnTo(s),
		PostLogoutRedirectURI: a.farewellURI(s),
		BackchannelLogoutURI:  s.origin + a.config.Mount + "/logout/backchannel",
		Scope:                 a.approvedScope(),
	}
}

func (a *App) scopeFor(requested string) []string {
	var asked []Privilege

	for name := range strings.FieldsSeq(requested) {
		if privilege, found := a.config.Privileges[name]; found {
			asked = append(asked, privilege)
		}
	}

	return withScopes(a.config.Scope, asked...)
}

func (a *App) mustPrivileges(names []string) []Privilege {
	held := make([]Privilege, 0, len(names))

	for _, name := range names {
		privilege, found := a.config.Privileges[name]
		if !found {
			panic(fmt.Sprintf("masks/web: Config.Privileges has no %s", name))
		}

		held = append(held, privilege)
	}

	return held
}

type LoginOptions struct {
	ReturnTo     string
	Organization string
	Privileges   []string
}

func (a *App) LoginURL(asked LoginOptions) string {
	query := url.Values{}

	if held := localPath(asked.ReturnTo); held != "" {
		query.Set("return_to", held)
	}

	if key := masks.OrganizationKey(asked.Organization); key != "" {
		query.Set("organization", key)
	}

	if len(asked.Privileges) > 0 {
		a.mustPrivileges(asked.Privileges)
		query.Set("privilege", strings.Join(asked.Privileges, " "))
	}

	if len(query) == 0 {
		return a.config.Mount + "/"
	}

	return a.config.Mount + "/?" + query.Encode()
}

func (a *App) LogoutPath() string {
	return a.config.Mount + "/logout"
}

func (a *App) HandshakePath() string {
	return a.config.Mount + "/handshake"
}

func (a *App) Handler() http.Handler {
	return a.handler
}

func (a *App) Client(r *http.Request) (*masks.Client, error) {
	s, err := a.site(r)
	if err != nil {
		return nil, err
	}

	if s.held == nil {
		return nil, ErrNotConnected
	}

	return a.signIn(s), nil
}

func (a *App) Connected(r *http.Request) (bool, error) {
	held, err := a.config.Credentials.Load(r)

	return held != nil, err
}

func (a *App) Registered(r *http.Request) (bool, error) {
	s, err := a.site(r)
	if err != nil {
		return false, err
	}

	return registered(r.Context(), s)
}

func registered(ctx context.Context, s *site) (bool, error) {
	if s.held == nil {
		return false, nil
	}

	if s.held.RegistrationAccessToken == "" {
		return true, nil
	}

	_, err := s.issuer.ReadRegistration(ctx, s.held.Registration())

	var refused *masks.Error
	if errors.As(err, &refused) && slices.Contains([]int{http.StatusUnauthorized, http.StatusForbidden, http.StatusNotFound}, refused.Status) {
		return false, nil
	}

	return err == nil, err
}

var (
	ErrNotConnected       = errors.New("masks/web: this app has not shaken hands with its issuer")
	ErrForeignCredentials = errors.New("masks/web: the app's credentials were issued by another issuer")
)

type Forbidden struct {
	Code        string
	Description string
	Scope       string
}

func (f *Forbidden) Error() string {
	return "masks/web: " + f.Code + ": " + f.Description
}

func wantsJSON(r *http.Request) bool {
	if r.Header.Get("X-Requested-With") == "XMLHttpRequest" {
		return true
	}

	if held, _, err := mime.ParseMediaType(r.Header.Get("Content-Type")); err == nil && held == "application/json" {
		return true
	}

	accept := r.Header.Get("Accept")

	return accept != "" && !strings.Contains(accept, "text/html") &&
		(strings.Contains(accept, "json") || !strings.Contains(accept, "*/*"))
}

func writeJSON(w http.ResponseWriter, status int, body any) {
	w.Header().Set("Content-Type", "application/json")
	w.Header().Set("Cache-Control", "no-store")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(body)
}

func (a *App) refuse(w http.ResponseWriter, r *http.Request, status int, code, description string) {
	if wantsJSON(r) {
		writeJSON(w, status, map[string]string{"error": code, "error_description": description})
		return
	}

	w.Header().Set("Content-Type", "text/plain; charset=utf-8")
	w.Header().Set("Cache-Control", "no-store")
	w.Header().Set("X-Content-Type-Options", "nosniff")
	w.WriteHeader(status)
	fmt.Fprintf(w, "%s: %s\n", code, description)
}

func (a *App) failed(w http.ResponseWriter, r *http.Request, err error) {
	var refused *masks.Error
	if errors.As(err, &refused) {
		a.refuse(w, r, http.StatusBadRequest, refused.Code, refused.Description)
		return
	}

	var bad *masks.InvalidTokenError
	if errors.As(err, &bad) {
		a.refuse(w, r, http.StatusBadRequest, "invalid_token", bad.Description)
		return
	}

	a.refuse(w, r, http.StatusServiceUnavailable, "temporarily_unavailable", "masks could not be reached")
}

type provenance int

const (
	unproven provenance = iota
	sameSite
	crossSite
)

func provenanceOf(r *http.Request) provenance {
	switch r.Header.Get("Sec-Fetch-Site") {
	case "same-origin", "none":
		return sameSite
	case "":
	default:
		return crossSite
	}

	from := r.Header.Get("Origin")
	if from == "" {
		return unproven
	}

	if parsed, err := url.Parse(from); err == nil && strings.EqualFold(parsed.Host, r.Host) {
		return sameSite
	}

	return crossSite
}
