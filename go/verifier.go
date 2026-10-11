package masks

import (
	"context"
	"crypto"
	"crypto/subtle"
	"encoding/base64"
	"encoding/json"
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
)

var (
	tokenAlgorithms = []jose.SignatureAlgorithm{jose.RS256, jose.ES256}
	proofAlgorithms = []jose.SignatureAlgorithm{jose.ES256, jose.ES384, jose.ES512, jose.PS256, jose.PS384, jose.PS512, jose.RS256}
)

type Claims struct {
	Issuer       string          `json:"iss"`
	Subject      string          `json:"sub"`
	Audience     jwt.Audience    `json:"aud"`
	Expiry       int64           `json:"exp"`
	IssuedAt     int64           `json:"iat"`
	ID           string          `json:"jti"`
	ClientID     string          `json:"client_id"`
	Scope        string          `json:"scope"`
	Tenant       *Tenant         `json:"tenant,omitempty"`
	Act          json.RawMessage `json:"act,omitempty"`
	Confirmation *struct {
		Thumbprint string `json:"jkt"`
	} `json:"cnf,omitempty"`
}

func (c *Claims) Scopes() []string {
	return strings.Fields(c.Scope)
}

func (c *Claims) HasScope(scope string) bool {
	return slices.Contains(c.Scopes(), scope)
}

func (c *Claims) Bound() bool {
	return c.Confirmation != nil && c.Confirmation.Thumbprint != ""
}

type Verifier struct {
	Issuer    *Issuer
	Audience  []string
	PublicURL string

	replays sync.Map
	swept   time.Time
	sweep   sync.Mutex
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
	standard := jwt.Claims{}

	if err := parsed.Claims(key.Key, claims, &standard); err != nil {
		return nil, invalid("that token was not signed by %s", v.Issuer.URL)
	}

	if claims.ID == "" || claims.Expiry == 0 {
		return nil, invalid("a token carries jti and exp")
	}

	expected := jwt.Expected{Issuer: v.Issuer.URL, AnyAudience: jwt.Audience(v.Audience), Time: time.Now()}

	if err := standard.ValidateWithLeeway(expected, verifyLeeway); err != nil {
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
			challenge := fmt.Sprintf(`error="invalid_token", error_description=%q`, strings.TrimPrefix(err.Error(), ErrInvalidToken.Error()+": "))
			response.Header().Add("WWW-Authenticate", "Bearer "+challenge)
			response.Header().Add("WWW-Authenticate", DPoP+" "+challenge+` algs="ES256 ES384 ES512 PS256 PS384 PS512 RS256"`)
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

func (v *Verifier) proven(request *http.Request, token, thumbprint string) error {
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

	held, err := carried.Thumbprint(crypto.SHA256)
	if err != nil || subtle.ConstantTimeCompare([]byte(base64.RawURLEncoding.EncodeToString(held)), []byte(thumbprint)) != 1 {
		return invalid("that proof was signed by another key than the token is held to")
	}

	if !strings.EqualFold(claims.Method, request.Method) {
		return invalid("that proof was made for another method")
	}

	target, err := withoutQuery(v.target(request))
	if err != nil || !sameTarget(claims.Target, target) {
		return invalid("that proof was made for another URL")
	}

	made := time.Unix(claims.IssuedAt, 0)

	if time.Since(made) > proofWindow+verifyLeeway || time.Until(made) > verifyLeeway {
		return invalid("that proof was not made just now")
	}

	if subtle.ConstantTimeCompare([]byte(claims.Hash), []byte(tokenHash(token))) != 1 {
		return invalid("that proof was made for another token")
	}

	if claims.ID == "" || !v.first(thumbprint+":"+claims.ID) {
		return invalid("that proof has already been used")
	}

	return nil
}

func (v *Verifier) target(request *http.Request) string {
	if v.PublicURL != "" {
		return strings.TrimSuffix(v.PublicURL, "/") + request.URL.RequestURI()
	}

	scheme := "http"
	if request.TLS != nil {
		scheme = "https"
	}

	return scheme + "://" + request.Host + request.URL.RequestURI()
}

func sameTarget(left, right string) bool {
	tidy := func(value string) string {
		held, err := withoutQuery(value)
		if err != nil {
			return ""
		}

		parsed, err := url.Parse(held)
		if err != nil {
			return ""
		}

		parsed.Scheme = strings.ToLower(parsed.Scheme)
		parsed.Host = strings.ToLower(parsed.Host)

		if (parsed.Scheme == "https" && parsed.Port() == "443") || (parsed.Scheme == "http" && parsed.Port() == "80") {
			parsed.Host = parsed.Hostname()
		}

		if parsed.Path == "/" {
			parsed.Path = ""
		}

		return parsed.String()
	}

	held := tidy(left)

	return held != "" && held == tidy(right)
}

func (v *Verifier) first(id string) bool {
	now := time.Now()
	_, seen := v.replays.LoadOrStore(id, now)

	v.sweep.Lock()
	if now.Sub(v.swept) > proofWindow {
		v.swept = now
		v.replays.Range(func(key, value any) bool {
			if now.Sub(value.(time.Time)) > proofWindow+2*verifyLeeway {
				v.replays.Delete(key)
			}

			return true
		})
	}
	v.sweep.Unlock()

	return !seen
}

func typed(header jose.Header, want string) bool {
	held, _ := header.ExtraHeaders[jose.HeaderType].(string)

	return strings.EqualFold(strings.TrimPrefix(strings.ToLower(held), "application/"), want)
}

func invalid(format string, values ...any) error {
	return fmt.Errorf("%w: %s", ErrInvalidToken, fmt.Sprintf(format, values...))
}
