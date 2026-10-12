package masks

import (
	"context"
	"crypto/subtle"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"net/url"
	"slices"
	"strings"
	"sync"
	"time"

	"github.com/go-jose/go-jose/v4"
	"github.com/go-jose/go-jose/v4/jwt"
)

const (
	accessTokenType = "at+jwt"
	proofWindow     = 60 * time.Second
	verifyLeeway    = 30 * time.Second
	replayMemory    = proofWindow + 2*verifyLeeway
)

var (
	tokenAlgorithms = []jose.SignatureAlgorithm{jose.RS256, jose.ES256}
	proofAlgorithms = []jose.SignatureAlgorithm{jose.ES256, jose.ES384, jose.ES512, jose.PS256, jose.PS384, jose.PS512, jose.RS256}
	proofAlgs       = func() string {
		named := make([]string, len(proofAlgorithms))
		for index, algorithm := range proofAlgorithms {
			named[index] = string(algorithm)
		}

		return strings.Join(named, " ")
	}()
)

type Organization struct {
	ID   string `json:"id"`
	Key  string `json:"key"`
	Name string `json:"name"`
	Role string `json:"role"`
}

func (o *Organization) HasRole(roles ...string) bool {
	return o != nil && o.Role != "" && slices.Contains(roles, o.Role)
}

type Confirmation struct {
	Thumbprint string `json:"jkt"`
}

type Claims struct {
	jwt.Claims

	ClientID     string          `json:"client_id"`
	Scope        string          `json:"scope"`
	Tenant       *Tenant         `json:"tenant,omitempty"`
	Organization *Organization   `json:"org,omitempty"`
	Act          json.RawMessage `json:"act,omitempty"`
	Confirmation *Confirmation   `json:"cnf,omitempty"`
}

func (c *Claims) Scopes() []string {
	return strings.Fields(c.Scope)
}

func (c *Claims) HasScope(scope string) bool {
	for held := range strings.FieldsSeq(c.Scope) {
		if held == scope {
			return true
		}
	}

	return false
}

func (c *Claims) Bound() bool {
	return c.Confirmation != nil && c.Confirmation.Thumbprint != ""
}

type Verifier struct {
	Issuer    *Issuer
	Audience  []string
	PublicURL string
	Replay    ReplayStore

	memory MemoryReplayStore
	once   sync.Once
	public *url.URL
}

func NewVerifier(issuer *Issuer, audience ...string) *Verifier {
	return &Verifier{Issuer: issuer, Audience: audience}
}

func (v *Verifier) Verify(ctx context.Context, token string) (*Claims, error) {
	parsed, err := jwt.ParseSigned(token, tokenAlgorithms)
	if err != nil {
		return nil, invalid("that token is not a signed JWT: %v", err)
	}

	if len(parsed.Headers) != 1 {
		return nil, invalid("a token carries exactly one signature")
	}

	header := parsed.Headers[0]

	if !typed(header, accessTokenType) {
		return nil, invalid("that token is not typed %s", accessTokenType)
	}

	key, err := v.Issuer.key(ctx, header.KeyID)
	if err != nil {
		return nil, err
	}

	claims := &Claims{}

	if err := parsed.Claims(key.Key, claims); err != nil {
		return nil, invalid("that token was not signed by %s", v.Issuer.URL)
	}

	if claims.ID == "" || claims.Expiry == nil {
		return nil, invalid("a token carries jti and exp")
	}

	expected := jwt.Expected{Issuer: v.Issuer.URL, AnyAudience: jwt.Audience(v.Audience), Time: time.Now()}

	if err := claims.ValidateWithLeeway(expected, verifyLeeway); err != nil {
		return nil, invalid("%v", err)
	}

	return claims, nil
}

func (v *Verifier) Authenticate(request *http.Request) (*Claims, error) {
	scheme, token, found := strings.Cut(request.Header.Get("Authorization"), " ")
	if !found || token == "" {
		return nil, invalid("the request carries no token")
	}

	claims, err := v.Verify(request.Context(), token)
	if err != nil {
		return nil, err
	}

	switch {
	case strings.EqualFold(scheme, "Bearer") && !claims.Bound():
		return claims, nil
	case strings.EqualFold(scheme, DPoP) && claims.Bound():
		return claims, v.proven(request, token, claims.Confirmation.Thumbprint)
	case strings.EqualFold(scheme, "Bearer"):
		return nil, invalid("that token is held to a key and is presented with DPoP")
	default:
		return nil, invalid("that token is presented as a Bearer token")
	}
}

func (v *Verifier) Middleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(response http.ResponseWriter, request *http.Request) {
		claims, err := v.Authenticate(request)
		if err != nil {
			var refused *InvalidTokenError
			if !errors.As(err, &refused) {
				http.Error(response, "the token could not be checked", http.StatusServiceUnavailable)
				return
			}

			challenge := fmt.Sprintf(`error="invalid_token", error_description=%q`, refused.Description)
			response.Header().Add("WWW-Authenticate", "Bearer "+challenge)
			response.Header().Add("WWW-Authenticate", DPoP+" "+challenge+` algs="`+proofAlgs+`"`)
			http.Error(response, "unauthorized", http.StatusUnauthorized)

			return
		}

		next.ServeHTTP(response, request.WithContext(context.WithValue(request.Context(), claimsKey{}, claims)))
	})
}

type claimsKey struct{}

func ClaimsFrom(ctx context.Context) (*Claims, bool) {
	held, ok := ctx.Value(claimsKey{}).(*Claims)

	return held, ok
}

func (v *Verifier) proven(request *http.Request, token, bound string) error {
	presented := request.Header.Values(DPoP)
	if len(presented) != 1 || strings.Contains(presented[0], ",") {
		return invalid("exactly one DPoP proof is required")
	}

	parsed, err := jwt.ParseSigned(presented[0], proofAlgorithms)
	if err != nil || len(parsed.Headers) != 1 {
		return invalid("that proof is not a signed JWT")
	}

	header := parsed.Headers[0]

	if !typed(header, proofType) {
		return invalid("a proof is typed %s", proofType)
	}

	carried := header.JSONWebKey
	if carried == nil || !carried.IsPublic() || !carried.Valid() {
		return invalid("a proof carries the public key that signed it")
	}

	if _, symmetric := carried.Key.([]byte); symmetric {
		return invalid("a proof key is public")
	}

	claims := proofClaims{}

	if err := parsed.Claims(carried.Key, &claims); err != nil {
		return invalid("that proof was not signed by the key it carries")
	}

	held, err := thumbprint(*carried)
	if err != nil || subtle.ConstantTimeCompare([]byte(held), []byte(bound)) != 1 {
		return invalid("that proof was signed by another key than the token is held to")
	}

	if !strings.EqualFold(claims.Method, request.Method) {
		return invalid("that proof was made for another method")
	}

	if target, err := tidiedString(claims.Target); err != nil || target != tidied(v.target(request)) {
		return invalid("that proof was made for another URL")
	}

	made := time.Unix(claims.IssuedAt, 0)

	if time.Since(made) > proofWindow+verifyLeeway || time.Until(made) > verifyLeeway {
		return invalid("that proof was not made just now")
	}

	if subtle.ConstantTimeCompare([]byte(claims.Hash), []byte(tokenHash(token))) != 1 {
		return invalid("that proof was made for another token")
	}

	if claims.ID == "" {
		return invalid("a proof carries a jti")
	}

	first, err := v.replay().First(request.Context(), bound+":"+claims.ID, replayMemory)
	if err != nil {
		return fmt.Errorf("%w: %w", ErrReplayStore, err)
	}

	if !first {
		return invalid("that proof has already been used")
	}

	return nil
}

func (v *Verifier) replay() ReplayStore {
	if v.Replay != nil {
		return v.Replay
	}

	return &v.memory
}

func (v *Verifier) target(request *http.Request) *url.URL {
	v.once.Do(func() {
		if v.PublicURL != "" {
			v.public, _ = url.Parse(strings.TrimSuffix(v.PublicURL, "/"))
		}
	})

	held := *request.URL

	switch {
	case v.public != nil:
		held.Scheme, held.Host = v.public.Scheme, v.public.Host
		held.Path = v.public.Path + request.URL.Path
		held.RawPath = ""
	case request.TLS != nil:
		held.Scheme, held.Host = "https", request.Host
	default:
		held.Scheme, held.Host = "http", request.Host
	}

	return &held
}

func typed(header jose.Header, want string) bool {
	held, _ := header.ExtraHeaders[jose.HeaderType].(string)

	return strings.TrimPrefix(strings.ToLower(held), "application/") == want
}
