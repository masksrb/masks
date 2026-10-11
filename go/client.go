package masks

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strings"
	"time"
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

var devicePause = 5 * time.Second

type Client struct {
	Issuer *Issuer
	ID     string
	Secret string
	Method AuthMethod
	Key    *Key
	DPoP   *Key
}

type TokenRequest struct {
	Scope    []string
	Resource []string
}

type Token struct {
	AccessToken  string    `json:"access_token"`
	TokenType    string    `json:"token_type"`
	RefreshToken string    `json:"refresh_token,omitempty"`
	IDToken      string    `json:"id_token,omitempty"`
	Scope        string    `json:"scope,omitempty"`
	ExpiresIn    int64     `json:"expires_in,omitempty"`
	Expiry       time.Time `json:"expiry,omitzero"`
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
	interval := max(time.Duration(device.Interval)*time.Second, devicePause)

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
			interval += devicePause
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
	endpoint, err := c.Issuer.endpoint("token_endpoint", c.Issuer.Metadata.TokenEndpoint)
	if err != nil {
		return nil, err
	}

	held := &Token{}

	if err := c.post(ctx, endpoint, form, true, held); err != nil {
		return nil, err
	}

	if held.AccessToken == "" {
		return nil, &Error{Code: "server_error", Description: "the token endpoint answered without an access token"}
	}

	if held.ExpiresIn > 0 {
		held.Expiry = time.Now().Add(time.Duration(held.ExpiresIn) * time.Second)
	}

	if c.DPoP != nil && !held.Bound() {
		return nil, &Error{Code: "invalid_dpop_proof", Description: "the token endpoint answered with a token that is not held to this key"}
	}

	return held, nil
}

func (c *Client) post(ctx context.Context, endpoint string, form url.Values, proven bool, into any) error {
	nonce := ""

	for attempt := 0; ; attempt++ {
		request, err := c.request(ctx, endpoint, form, proven, nonce)
		if err != nil {
			return err
		}

		response, err := c.Issuer.settings.client.Do(request)
		if err != nil {
			return err
		}

		if wanted := response.Header.Get("DPoP-Nonce"); proven && c.DPoP != nil && attempt == 0 && wanted != "" &&
			response.StatusCode >= 400 && asksForNonce(response) {
			nonce = wanted
			response.Body.Close()

			continue
		}

		return decoded(response, into)
	}
}

func asksForNonce(response *http.Response) bool {
	if strings.Contains(response.Header.Get("WWW-Authenticate"), "use_dpop_nonce") {
		return true
	}

	body, _ := io.ReadAll(io.LimitReader(response.Body, readLimit))
	response.Body = io.NopCloser(strings.NewReader(string(body)))

	held := &Error{}

	return json.Unmarshal(body, held) == nil && held.Code == "use_dpop_nonce"
}

func decoded(response *http.Response, into any) error {
	defer response.Body.Close()

	if response.StatusCode >= 300 {
		return refused(response)
	}

	if into == nil {
		return nil
	}

	if err := json.NewDecoder(io.LimitReader(response.Body, readLimit)).Decode(into); err != nil {
		return errors.Join(errors.New("masks: the issuer answered with something other than JSON"), err)
	}

	return nil
}

func (c *Client) request(ctx context.Context, endpoint string, form url.Values, proven bool, nonce string) (*http.Request, error) {
	held := url.Values{}

	for name, values := range form {
		held[name] = append([]string(nil), values...)
	}

	request, err := http.NewRequestWithContext(ctx, http.MethodPost, endpoint, nil)
	if err != nil {
		return nil, err
	}

	if err := c.authenticate(request, held); err != nil {
		return nil, err
	}

	if proven && c.DPoP != nil {
		proof, err := c.DPoP.Proof(http.MethodPost, endpoint, "", nonce)
		if err != nil {
			return nil, err
		}

		request.Header.Set("DPoP", proof)
	}

	encoded := held.Encode()
	request.Body = io.NopCloser(strings.NewReader(encoded))
	request.ContentLength = int64(len(encoded))
	request.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	request.Header.Set("Accept", "application/json")

	return request, nil
}

type assertionClaims struct {
	Issuer   string `json:"iss"`
	Subject  string `json:"sub"`
	Audience string `json:"aud"`
	ID       string `json:"jti"`
	IssuedAt int64  `json:"iat"`
	Expiry   int64  `json:"exp"`
}

func (c *Client) authenticate(request *http.Request, form url.Values) error {
	if c.ID == "" {
		return errors.New("masks: a client needs its client_id")
	}

	switch method := c.method(); method {
	case ClientSecretBasic:
		request.SetBasicAuth(url.QueryEscape(c.ID), url.QueryEscape(c.Secret))
	case ClientSecretPost:
		form.Set("client_id", c.ID)
		form.Set("client_secret", c.Secret)
	case PrivateKeyJWT:
		if c.Key == nil {
			return errors.New("masks: private_key_jwt needs the client's Key")
		}

		now := time.Now()
		assertion, err := c.Key.sign("JWT", assertionClaims{
			Issuer:   c.ID,
			Subject:  c.ID,
			Audience: c.Issuer.URL,
			ID:       random(),
			IssuedAt: now.Unix(),
			Expiry:   now.Add(assertionLifetime).Unix(),
		}, false)
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
