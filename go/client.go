package masks

import (
	"context"
	"crypto/rand"
	"encoding/base64"
	"errors"
	"fmt"
	"maps"
	"net/http"
	"net/url"
	"strings"
	"time"

	"github.com/go-jose/go-jose/v4/jwt"
)

type AuthMethod string

const (
	ClientSecretBasic AuthMethod = "client_secret_basic"
	ClientSecretPost  AuthMethod = "client_secret_post"
	PrivateKeyJWT     AuthMethod = "private_key_jwt"
	NoAuth            AuthMethod = "none"
)

const (
	GrantClientCredentials = "client_credentials"
	GrantRefreshToken      = "refresh_token"
	GrantDeviceCode        = "urn:ietf:params:oauth:grant-type:device_code"

	assertionType     = "urn:ietf:params:oauth:client-assertion-type:jwt-bearer"
	assertionLifetime = time.Minute
	expiryLeeway      = 30 * time.Second
)

type Client struct {
	Issuer      *Issuer
	ID          string
	Secret      string
	Method      AuthMethod
	Key         *Key
	DPoP        *Key
	RedirectURI string
}

type TokenRequest struct {
	Scope    []string
	Resource []string
}

type Token struct {
	AccessToken     string       `json:"access_token"`
	TokenType       string       `json:"token_type"`
	RefreshToken    string       `json:"refresh_token,omitempty"`
	IssuedTokenType string       `json:"issued_token_type,omitempty"`
	IDToken         string       `json:"id_token,omitempty"`
	Delegations     []Delegation `json:"delegations,omitempty"`
	Scope           string       `json:"scope,omitempty"`
	ExpiresIn       int64        `json:"expires_in,omitempty"`
	Expiry          time.Time    `json:"expiry,omitzero"`
}

func (t *Token) Valid() bool {
	return t != nil && t.AccessToken != "" && (t.Expiry.IsZero() || time.Until(t.Expiry) > expiryLeeway)
}

func (t *Token) Bound() bool {
	return t != nil && strings.EqualFold(t.TokenType, DPoP)
}

func (t *Token) Scopes() []string {
	return strings.Fields(t.Scope)
}

type DeviceAuthorization struct {
	DeviceCode              string `json:"device_code"`
	UserCode                string `json:"user_code"`
	VerificationURI         string `json:"verification_uri"`
	VerificationURIComplete string `json:"verification_uri_complete,omitempty"`
	ExpiresIn               int64  `json:"expires_in"`
	Interval                int64  `json:"interval,omitempty"`

	expiry time.Time
}

func (c *Client) method() AuthMethod {
	switch {
	case c.Method != "":
		return c.Method
	case c.Secret != "":
		return ClientSecretBasic
	case c.Key != nil:
		return PrivateKeyJWT
	default:
		return NoAuth
	}
}

func (c *Client) ClientCredentials(ctx context.Context, asked TokenRequest) (*Token, error) {
	form := asked.form()
	form.Set("grant_type", GrantClientCredentials)

	return c.token(ctx, form)
}

func (c *Client) Refresh(ctx context.Context, refreshToken string, asked TokenRequest) (*Token, error) {
	form := asked.form()
	form.Set("grant_type", GrantRefreshToken)
	form.Set("refresh_token", refreshToken)

	return c.token(ctx, form)
}

func (c *Client) DeviceAuthorization(ctx context.Context, asked TokenRequest) (*DeviceAuthorization, error) {
	endpoint, err := c.Issuer.endpoint("device_authorization_endpoint", c.Issuer.Metadata.DeviceAuthorizationEndpoint)
	if err != nil {
		return nil, err
	}

	form := asked.form()
	form.Set("client_id", c.ID)

	held := &DeviceAuthorization{}

	if err := c.post(ctx, endpoint, form, false, held); err != nil {
		return nil, err
	}

	held.expiry = time.Now().Add(time.Duration(held.ExpiresIn) * time.Second)

	return held, nil
}

func (c *Client) AwaitDevice(ctx context.Context, device *DeviceAuthorization) (*Token, error) {
	step := c.Issuer.settings.pause
	interval := time.Duration(device.Interval) * time.Second

	if interval <= 0 {
		interval = step
	}

	form := url.Values{}
	form.Set("grant_type", GrantDeviceCode)
	form.Set("device_code", device.DeviceCode)

	for {
		if !device.expiry.IsZero() && time.Now().After(device.expiry) {
			return nil, &Error{Code: "expired_token", Description: "the code expired before anyone approved it"}
		}

		select {
		case <-ctx.Done():
			return nil, ctx.Err()
		case <-time.After(interval):
		}

		token, err := c.token(ctx, form)

		switch {
		case HasCode(err, "authorization_pending"):
			continue
		case HasCode(err, "slow_down"):
			interval += step
			continue
		default:
			return token, err
		}
	}
}

func (c *Client) Revoke(ctx context.Context, token, hint string) error {
	endpoint, err := c.Issuer.endpoint("revocation_endpoint", c.Issuer.Metadata.RevocationEndpoint)
	if err != nil {
		return err
	}

	form := url.Values{}
	form.Set("token", token)

	if hint != "" {
		form.Set("token_type_hint", hint)
	}

	return c.post(ctx, endpoint, form, false, nil)
}

func (asked TokenRequest) form() url.Values {
	form := url.Values{}

	if len(asked.Scope) > 0 {
		form.Set("scope", strings.Join(asked.Scope, " "))
	}

	for _, resource := range asked.Resource {
		form.Add("resource", resource)
	}

	return form
}

func (c *Client) token(ctx context.Context, form url.Values) (*Token, error) {
	return c.grant(ctx, form, c.DPoP != nil)
}

func (c *Client) grant(ctx context.Context, form url.Values, held bool) (*Token, error) {
	endpoint, err := c.Issuer.endpoint("token_endpoint", c.Issuer.Metadata.TokenEndpoint)
	if err != nil {
		return nil, err
	}

	granted := &Token{}

	if err := c.post(ctx, endpoint, form, true, granted); err != nil {
		return nil, err
	}

	if granted.AccessToken == "" {
		return nil, &Error{Code: "server_error", Description: "the token endpoint answered without an access token"}
	}

	if granted.ExpiresIn > 0 {
		granted.Expiry = time.Now().Add(time.Duration(granted.ExpiresIn) * time.Second)
	}

	if held && !granted.Bound() {
		return nil, &Error{Code: "invalid_dpop_proof", Description: "the token endpoint answered with a token that is not held to this key"}
	}

	return granted, nil
}

func (c *Client) post(ctx context.Context, endpoint string, form url.Values, proven bool, into any) error {
	return c.call(ctx, http.MethodPost, endpoint, form, proven, into)
}

func (c *Client) call(ctx context.Context, method, endpoint string, form url.Values, proven bool, into any) error {
	target, err := url.Parse(endpoint)
	if err != nil {
		return err
	}

	proving := proven && c.DPoP != nil
	nonce := ""

	if proving {
		nonce = c.Issuer.nonces.load(target)
	}

	response, err := c.send(ctx, method, endpoint, form, proving, nonce)
	if err != nil {
		return err
	}

	if !proving {
		return decoded(response, into)
	}

	wanted := c.Issuer.nonces.learn(target, response)
	err = decoded(response, into)

	if wanted == "" || wanted == nonce || !HasCode(err, "use_dpop_nonce") {
		return err
	}

	response, err = c.send(ctx, method, endpoint, form, proving, wanted)
	if err != nil {
		return err
	}

	c.Issuer.nonces.learn(target, response)

	return decoded(response, into)
}

func (c *Client) send(ctx context.Context, method, endpoint string, form url.Values, proving bool, nonce string) (*http.Response, error) {
	header := http.Header{}

	if err := c.authenticate(header, form); err != nil {
		return nil, err
	}

	if proving {
		proof, err := c.DPoP.Proof(method, endpoint, "", nonce)
		if err != nil {
			return nil, err
		}

		header.Set("DPoP", proof)
	}

	request, err := http.NewRequestWithContext(ctx, method, endpoint, strings.NewReader(form.Encode()))
	if err != nil {
		return nil, err
	}

	maps.Copy(request.Header, header)
	request.Header.Set("Content-Type", "application/x-www-form-urlencoded")

	return c.Issuer.settings.do(request)
}

func (c *Client) authenticate(header http.Header, form url.Values) error {
	if c.ID == "" {
		return errors.New("masks: a client needs its client_id")
	}

	switch method := c.method(); method {
	case ClientSecretBasic:
		header.Set("Authorization", "Basic "+base64.StdEncoding.EncodeToString([]byte(url.QueryEscape(c.ID)+":"+url.QueryEscape(c.Secret))))
	case ClientSecretPost:
		form.Set("client_id", c.ID)
		form.Set("client_secret", c.Secret)
	case PrivateKeyJWT:
		if c.Key == nil {
			return errors.New("masks: private_key_jwt needs the client's Key")
		}

		now := time.Now()
		assertion, err := c.Key.assert(jwt.Claims{
			Issuer:   c.ID,
			Subject:  c.ID,
			Audience: jwt.Audience{c.Issuer.URL},
			ID:       rand.Text(),
			IssuedAt: jwt.NewNumericDate(now),
			Expiry:   jwt.NewNumericDate(now.Add(assertionLifetime)),
		})
		if err != nil {
			return err
		}

		form.Set("client_id", c.ID)
		form.Set("client_assertion_type", assertionType)
		form.Set("client_assertion", assertion)
	case NoAuth:
		form.Set("client_id", c.ID)
	default:
		return fmt.Errorf("masks: %q is not a way a client authenticates", method)
	}

	return nil
}
