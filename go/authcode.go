package masks

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"errors"
	"net/url"
	"regexp"
	"slices"
	"strconv"
	"strings"
	"time"
)

const (
	GrantAuthorizationCode = "authorization_code"
	ScopeOpenID            = "openid"
	ScopeOfflineAccess     = "offline_access"
	ScopeOrganization      = "organization"
)

var (
	DefaultScope    = []string{ScopeOpenID, "profile", "email"}
	organizationKey = regexp.MustCompile(`\A[a-z0-9][a-z0-9-]*\z`)
	verifierEntropy = 64
)

type AuthRequest struct {
	Scope        []string
	Resource     []string
	Organization string
	Prompt       string
	MaxAge       time.Duration
}

type Authorization struct {
	URL      string   `json:"-"`
	State    string   `json:"state"`
	Nonce    string   `json:"nonce,omitempty"`
	Verifier string   `json:"verifier"`
	Resource []string `json:"resource,omitempty"`
	Provider string   `json:"provider,omitempty"`
	MaxAge   int64    `json:"max_age,omitempty"`
}

type SignIn struct {
	Token    *Token
	Identity *Identity
}

func OrganizationKey(value string) string {
	held := strings.ToLower(strings.TrimSpace(value))

	if !organizationKey.MatchString(held) {
		return ""
	}

	return held
}

func (c *Client) AuthCodeURL(asked AuthRequest) (*Authorization, error) {
	endpoint, err := c.Issuer.endpoint("authorization_endpoint", c.Issuer.Metadata.AuthorizationEndpoint)
	if err != nil {
		return nil, err
	}

	if c.ID == "" || c.RedirectURI == "" {
		return nil, errors.New("masks: signing in needs the client's ID and RedirectURI")
	}

	scope := asked.Scope
	if len(scope) == 0 {
		scope = DefaultScope
	}

	verifier := make([]byte, verifierEntropy)
	rand.Read(verifier)

	held := &Authorization{
		State:    rand.Text() + rand.Text(),
		Verifier: base64.RawURLEncoding.EncodeToString(verifier),
		Resource: asked.Resource,
	}

	challenge := sha256.Sum256([]byte(held.Verifier))

	query := url.Values{}
	query.Set("response_type", "code")
	query.Set("client_id", c.ID)
	query.Set("redirect_uri", c.RedirectURI)
	query.Set("scope", strings.Join(scope, " "))
	query.Set("state", held.State)
	query.Set("code_challenge", base64.RawURLEncoding.EncodeToString(challenge[:]))
	query.Set("code_challenge_method", "S256")

	if slices.Contains(scope, ScopeOpenID) {
		held.Nonce = rand.Text() + rand.Text()
		query.Set("nonce", held.Nonce)
	}

	for _, resource := range asked.Resource {
		query.Add("resource", resource)
	}

	if asked.Prompt != "" {
		query.Set("prompt", asked.Prompt)
	}

	if asked.MaxAge > 0 {
		held.MaxAge = int64(asked.MaxAge / time.Second)
		query.Set("max_age", strconv.FormatInt(held.MaxAge, 10))
	}

	if key := OrganizationKey(asked.Organization); key != "" {
		query.Set("organization", key)
	}

	target, err := url.Parse(endpoint)
	if err != nil {
		return nil, err
	}

	merged := target.Query()
	for name, values := range query {
		merged[name] = values
	}

	target.RawQuery = merged.Encode()
	held.URL = target.String()

	return held, nil
}

func (c *Client) Complete(ctx context.Context, returned url.Values, pending *Authorization) (*SignIn, error) {
	if pending == nil || !sameString(returned.Get("state"), pending.State) {
		return nil, refuse("state_mismatch")
	}

	if named := strings.TrimSuffix(returned.Get("iss"), "/"); named != c.Issuer.URL {
		return nil, &Refused{Code: "invalid_issuer", Description: "that answer came from " + strconv.Quote(named) + " instead of " + c.Issuer.URL}
	}

	if code := returned.Get("error"); code != "" {
		return nil, &Refused{Code: code, Description: returned.Get("error_description")}
	}

	code := returned.Get("code")
	if code == "" {
		return nil, refuse("no_callback_code")
	}

	form := TokenRequest{Resource: pending.Resource}.form()
	form.Set("grant_type", GrantAuthorizationCode)
	form.Set("code", code)
	form.Set("redirect_uri", c.RedirectURI)
	form.Set("code_verifier", pending.Verifier)

	token, err := c.token(ctx, form)
	if err != nil {
		return nil, err
	}

	signed := &SignIn{Token: token}

	if pending.Nonce == "" {
		return signed, nil
	}

	if token.IDToken == "" {
		return nil, invalid("no_id_token")
	}

	identity, err := c.VerifyIDToken(ctx, token.IDToken)
	if err != nil {
		return nil, err
	}

	if !sameString(identity.Nonce, pending.Nonce) {
		return nil, invalid("id_token_other_sign_in")
	}

	if identity.AccessTokenHash != "" && !sameString(identity.AccessTokenHash, accessTokenHash(token.AccessToken)) {
		return nil, invalid("id_token_other_access_token")
	}

	if pending.MaxAge > 0 && (identity.AuthTime == 0 ||
		time.Since(time.Unix(identity.AuthTime, 0)) > time.Duration(pending.MaxAge)*time.Second+verifyLeeway) {
		return nil, invalid("too_old")
	}

	signed.Identity = identity

	return signed, nil
}

type EndSession struct {
	IDTokenHint           string
	PostLogoutRedirectURI string
	State                 string
}

func (c *Client) EndSessionURL(asked EndSession) (string, error) {
	endpoint, err := c.Issuer.endpoint("end_session_endpoint", c.Issuer.Metadata.EndSessionEndpoint)
	if err != nil {
		return "", err
	}

	target, err := url.Parse(endpoint)
	if err != nil {
		return "", err
	}

	query := target.Query()
	query.Set("client_id", c.ID)

	for name, value := range map[string]string{
		"id_token_hint":            asked.IDTokenHint,
		"post_logout_redirect_uri": asked.PostLogoutRedirectURI,
		"state":                    asked.State,
	} {
		if value != "" {
			query.Set(name, value)
		}
	}

	target.RawQuery = query.Encode()

	return target.String(), nil
}
