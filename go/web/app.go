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

const discoveryLifetime = time.Hour

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
	Manages     func(*http.Request, *Person) bool
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
	issuer *masks.Issuer
	at     time.Time
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

	a.lock.Lock()
	held := a.issuers[named]
	a.lock.Unlock()

	if held != nil && time.Since(held.at) < discoveryLifetime {
		return held.issuer, nil
	}

	ctx, cancel := context.WithTimeout(context.WithoutCancel(r.Context()), 30*time.Second)
	defer cancel()

	found, err := masks.Discover(ctx, named, a.config.Options...)
	if err != nil {
		if held != nil {
			return held.issuer, nil
		}

		return nil, err
	}

	a.lock.Lock()
	if held != nil {
		held.at = time.Now()
		found = held.issuer
	} else {
		a.issuers[named] = &discovered{issuer: found, at: time.Now()}
	}
	a.lock.Unlock()

	return found, nil
}

func (a *App) site(r *http.Request) (*site, error) {
	issuer, err := a.issuerFor(r)
	if err != nil {
		return nil, err
	}

	resource := a.config.Resource

	if a.config.ResourceFor != nil {
		if resource, err = a.config.ResourceFor(r); err != nil {
			return nil, err
		}
	}

	parsed, err := url.Parse(resource)
	if err != nil || parsed.Host == "" || (parsed.Scheme != "https" && !(a.config.PlainHTTP && parsed.Scheme == "http")) {
		return nil, fmt.Errorf("masks/web: %q is not an absolute https resource URL", resource)
	}

	held, err := a.config.Credentials.Load(r)
	if err != nil {
		return nil, err
	}

	return &site{issuer: issuer, resource: resource, origin: parsed.Scheme + "://" + parsed.Host, held: held}, nil
}

func (s *site) client(redirect string) *masks.Client {
	if s.held == nil {
		return &masks.Client{Issuer: s.issuer}
	}

	return &masks.Client{Issuer: s.issuer, ID: s.held.ClientID, Secret: s.held.ClientSecret, Method: masks.ClientSecretBasic, RedirectURI: redirect}
}

func (a *App) signIn(s *site) *masks.Client {
	return s.client(s.origin + a.config.Mount + "/callback")
}

func (a *App) farewellURI(s *site) string {
	return s.origin + a.config.Mount + "/logout/return"
}

func (a *App) returnTo(s *site) string {
	return s.origin + a.config.Mount + "/handshake/callback"
}

func (a *App) approvedScope() []string {
	asked := slices.Clone(a.config.Scope)

	for _, name := range a.names {
		for _, scope := range a.config.Privileges[name].Scope {
			if !slices.Contains(asked, scope) {
				asked = append(asked, scope)
			}
		}
	}

	if a.config.Namespace != "" {
		asked = slices.DeleteFunc(asked, func(scope string) bool { return strings.HasPrefix(scope, a.config.Namespace) })
		asked = append(asked, a.config.Namespace)
	}

	if a.config.Delegates {
		asked = append(asked, masks.ScopeDelegate)
	}

	return asked
}

func (a *App) handshake(s *site) *masks.Handshake {
	name := a.config.Name
	if name == "" {
		name = strings.TrimPrefix(strings.TrimPrefix(s.origin, "https://"), "http://")
	}

	redirects := []string{s.origin + a.config.Mount + "/callback"}

	if a.config.Delegates {
		redirects = append(redirects, s.origin+localPath(a.config.DelegationPath))
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
	asked := slices.Clone(a.config.Scope)
	extra := false

	for name := range strings.FieldsSeq(requested) {
		privilege, found := a.config.Privileges[name]
		if !found {
			continue
		}

		for _, scope := range privilege.Scope {
			if !slices.Contains(asked, scope) {
				asked = append(asked, scope)
				extra = true
			}
		}
	}

	if !extra {
		return a.config.Scope
	}

	return asked
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

	if s.held == nil {
		return false, nil
	}

	if s.held.RegistrationAccessToken == "" {
		return true, nil
	}

	_, err = s.issuer.ReadRegistration(r.Context(), s.held.Registration())

	var refused *masks.Error
	if errors.As(err, &refused) && slices.Contains([]int{http.StatusUnauthorized, http.StatusForbidden, http.StatusNotFound}, refused.Status) {
		return false, nil
	}

	return err == nil, err
}

var ErrNotConnected = errors.New("masks/web: this app has not shaken hands with its issuer")

type refusal struct {
	code        string
	description string
	scope       string
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

func sameOrigin(r *http.Request) bool {
	switch r.Header.Get("Sec-Fetch-Site") {
	case "same-origin", "none":
		return true
	case "":
	default:
		return false
	}

	from := r.Header.Get("Origin")
	if from == "" {
		return true
	}

	parsed, err := url.Parse(from)

	return err == nil && strings.EqualFold(parsed.Host, r.Host)
}
