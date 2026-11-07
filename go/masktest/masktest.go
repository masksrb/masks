package masktest

import (
	"crypto"
	"crypto/rand"
	"crypto/rsa"
	"crypto/sha256"
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

const (
	ClientSecretBasic = "client_secret_basic"
	ClientSecretPost  = "client_secret_post"
	PrivateKeyJWT     = "private_key_jwt"
	NoAuth            = "none"

	GrantAuthorizationCode = "authorization_code"
	GrantClientCredentials = "client_credentials"
	GrantRefreshToken      = "refresh_token"
	GrantDeviceCode        = "urn:ietf:params:oauth:grant-type:device_code"
	GrantTokenExchange     = "urn:ietf:params:oauth:grant-type:token-exchange"

	TokenTypeAccessToken         = "urn:ietf:params:oauth:token-type:access_token"
	TokenTypeUpstreamAccessToken = "urn:masks:params:oauth:token-type:upstream_access_token"

	AccessTokenType        = "at+jwt"
	LogoutTokenType        = "logout+jwt"
	BackchannelLogoutEvent = "http://schemas.openid.net/event/backchannel-logout"

	ScopeOpenID   = "openid"
	ScopeDelegate = "masks:delegate:"

	dpopHeader    = "DPoP"
	proofType     = "dpop+jwt"
	assertionType = "urn:ietf:params:oauth:client-assertion-type:jwt-bearer"
)

var proofAlgorithms = []jose.SignatureAlgorithm{jose.ES256, jose.ES384, jose.ES512, jose.PS256, jose.PS384, jose.PS512, jose.RS256}

type Client struct {
	Secret string
	Method string
	JWKS   jose.JSONWebKeySet
	Scope  string

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

type code struct {
	client       string
	redirect     string
	challenge    string
	nonce        string
	scope        string
	organization string
	resource     []string
}

type Actor struct {
	Subject string
	Name    string
	Email   string
	Role    string
}

type proofClaims struct {
	ID       string `json:"jti"`
	Method   string `json:"htm"`
	Target   string `json:"htu"`
	IssuedAt int64  `json:"iat"`
	Hash     string `json:"ath,omitempty"`
	Nonce    string `json:"nonce,omitempty"`
}

type Fake struct {
	t        testing.TB
	server   *httptest.Server
	signing  *rsa.PrivateKey
	kid      string
	Audience string

	lock          sync.Mutex
	clients       map[string]*Client
	registrations map[string]string
	Initial       map[string]string
	Pending       int
	slowed        bool
	Revoked       []string
	assertions    map[string]bool
	Nonce         string
	ForeignURI    bool
	live          map[string]liveToken
	EnrolledBy    map[string]string
	Seen          map[string]url.Values
	StaleActive   bool
	AuthTime      int64
	IssuedAs      string
	codes         map[string]code
	subjects      map[string]string
	Actor         Actor
	Declined      bool
	Asked         url.Values
	Handshake     url.Values
	Ended         url.Values
	UserinfoName  string
	UpstreamDown  bool
}

func New(t testing.TB) *Fake {
	t.Helper()

	signing, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		t.Fatal(err)
	}

	held := &Fake{
		t:             t,
		signing:       signing,
		kid:           "signing-1",
		Audience:      "https://files.example",
		clients:       map[string]*Client{},
		registrations: map[string]string{},
		Initial:       map[string]string{},
		assertions:    map[string]bool{},
		live:          map[string]liveToken{},
		EnrolledBy:    map[string]string{},
		Seen:          map[string]url.Values{},
		codes:         map[string]code{},
		subjects:      map[string]string{},
		Actor:         Actor{Subject: "ada", Name: "Ada Lovelace", Email: "ada@example.com", Role: "owner"},
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

func (f *Fake) URL() string {
	return f.server.URL
}

func (f *Fake) Lock() {
	f.lock.Lock()
}

func (f *Fake) Unlock() {
	f.lock.Unlock()
}

func (f *Fake) Add(id string, client *Client) {
	f.lock.Lock()
	defer f.lock.Unlock()

	if client.refresh == nil {
		client.refresh = map[string]bool{}
	}

	f.clients[id] = client
}

func (f *Fake) Issue(claims map[string]any, typ string) string {
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

func (f *Fake) AccessToken(id, scope, jkt string) string {
	return f.accessTokenFor(id, id, scope, jkt)
}

func (f *Fake) LogoutToken(claims map[string]any) string {
	merged := map[string]any{
		"iss":    f.URL(),
		"iat":    time.Now().Unix(),
		"exp":    time.Now().Add(2 * time.Minute).Unix(),
		"jti":    rand.Text(),
		"events": map[string]any{BackchannelLogoutEvent: map[string]any{}},
	}

	for name, value := range claims {
		merged[name] = value
	}

	return f.Issue(merged, LogoutTokenType)
}

func (f *Fake) accessTokenFor(subject, id, scope, jkt string) string {
	claims := map[string]any{
		"iss":       f.URL(),
		"sub":       subject,
		"aud":       f.Audience,
		"exp":       time.Now().Add(time.Hour).Unix(),
		"iat":       time.Now().Unix(),
		"jti":       rand.Text(),
		"client_id": id,
		"scope":     scope,
	}

	if jkt != "" {
		claims["cnf"] = map[string]string{"jkt": jkt}
	}

	return f.Issue(claims, AccessTokenType)
}

func typed(header jose.Header, want string) bool {
	held, _ := header.ExtraHeaders[jose.HeaderType].(string)

	return strings.TrimPrefix(strings.ToLower(held), "application/") == want
}

func thumbprint(key jose.JSONWebKey) (string, error) {
	held, err := key.Thumbprint(crypto.SHA256)
	if err != nil {
		return "", err
	}

	return base64.RawURLEncoding.EncodeToString(held), nil
}

func accessTokenHash(accessToken string) string {
	sum := sha256.Sum256([]byte(accessToken))

	return base64.RawURLEncoding.EncodeToString(sum[:len(sum)/2])
}

func WriteJSON(response http.ResponseWriter, status int, body any) {
	response.Header().Set("Content-Type", "application/json")
	response.WriteHeader(status)
	_ = json.NewEncoder(response).Encode(body)
}

func OAuthError(response http.ResponseWriter, status int, code string) {
	WriteJSON(response, status, map[string]string{"error": code, "error_description": code + " from the fake"})
}
