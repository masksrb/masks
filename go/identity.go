package masks

import (
	"context"
	"crypto/sha256"
	"crypto/subtle"
	"encoding/base64"
	"encoding/json"
	"maps"
	"net/http"
	"slices"
	"time"

	"github.com/go-jose/go-jose/v4/jwt"
)

const (
	AvatarPhoto     = "photo"
	AvatarIdenticon = "identicon"
	AvatarInitials  = "initials"
)

type Identity struct {
	jwt.Claims

	Name              string            `json:"name,omitempty"`
	PreferredUsername string            `json:"preferred_username,omitempty"`
	Email             string            `json:"email,omitempty"`
	EmailVerified     bool              `json:"email_verified,omitempty"`
	Picture           string            `json:"picture,omitempty"`
	Avatars           map[string]string `json:"masks:avatars,omitempty"`
	Tenant            *Tenant           `json:"tenant,omitempty"`
	Organization      *Organization     `json:"org,omitempty"`
	Organizations     []Organization    `json:"orgs,omitempty"`
	Groups            []string          `json:"groups,omitempty"`
	Nonce             string            `json:"nonce,omitempty"`
	SessionID         string            `json:"sid,omitempty"`
	AuthTime          int64             `json:"auth_time,omitempty"`
	AccessTokenHash   string            `json:"at_hash,omitempty"`
	AuthorizedParty   string            `json:"azp,omitempty"`

	Raw map[string]json.RawMessage `json:"-"`
}

func (i *Identity) UnmarshalJSON(data []byte) error {
	type plain Identity

	held := plain{}

	if err := json.Unmarshal(data, &held); err != nil {
		return err
	}

	if err := json.Unmarshal(data, &held.Raw); err != nil {
		return err
	}

	*i = Identity(held)

	return nil
}

func (i *Identity) MarshalJSON() ([]byte, error) {
	if i.Raw != nil {
		return json.Marshal(i.Raw)
	}

	type plain Identity

	return json.Marshal((*plain)(i))
}

func (i *Identity) Claim(name string, into any) bool {
	held, found := i.Raw[name]

	return found && json.Unmarshal(held, into) == nil
}

func (i *Identity) Photo() string {
	if i.Picture != "" {
		return i.Picture
	}

	if photo := i.Avatars[AvatarPhoto]; photo != "" {
		return photo
	}

	return i.Avatars[AvatarIdenticon]
}

func (i *Identity) Merged(over *Identity, names ...string) (*Identity, error) {
	held := maps.Clone(i.Raw)
	if held == nil {
		held = map[string]json.RawMessage{}
	}

	for name, value := range over.Raw {
		if len(names) == 0 || slices.Contains(names, name) {
			held[name] = value
		}
	}

	return identityFrom(held)
}

func (i *Identity) Kept(names ...string) (*Identity, error) {
	held := map[string]json.RawMessage{}

	for _, name := range names {
		if value, found := i.Raw[name]; found {
			held[name] = value
		}
	}

	return identityFrom(held)
}

func identityFrom(raw map[string]json.RawMessage) (*Identity, error) {
	encoded, err := json.Marshal(raw)
	if err != nil {
		return nil, err
	}

	held := &Identity{}

	return held, json.Unmarshal(encoded, held)
}

func (c *Client) VerifyIDToken(ctx context.Context, raw string) (*Identity, error) {
	held := &Identity{}

	if err := c.Issuer.verified(ctx, raw, []string{"jwt", ""}, held); err != nil {
		return nil, err
	}

	if held.Subject == "" || held.Expiry == nil || held.IssuedAt == nil {
		return nil, invalid("missing_claims", "sub, exp, and iat")
	}

	expected := jwt.Expected{Issuer: c.Issuer.URL, AnyAudience: jwt.Audience{c.ID}, Time: time.Now()}

	if err := held.ValidateWithLeeway(expected, verifyLeeway); err != nil {
		return nil, unverified(err)
	}

	if (len(held.Audience) > 1 || held.AuthorizedParty != "") && held.AuthorizedParty != c.ID {
		return nil, invalid("id_token_other_client")
	}

	return held, nil
}

func (i *Issuer) verified(ctx context.Context, raw string, types []string, into any) error {
	parsed, err := jwt.ParseSigned(raw, tokenAlgorithms)
	if err != nil {
		return &InvalidToken{Code: "invalid_token", Description: Saying("not_a_jwt"), cause: err}
	}

	if len(parsed.Headers) != 1 {
		return invalid("not_a_jwt")
	}

	header := parsed.Headers[0]

	if !slices.ContainsFunc(types, func(want string) bool { return typed(header, want) }) {
		return invalid("wrong_type", typeOf(header), types[0])
	}

	key, err := i.key(ctx, header.KeyID)
	if err != nil {
		return err
	}

	if err := parsed.Claims(key.Key, into); err != nil {
		return invalid("not_signed_by", i.URL)
	}

	return nil
}

func accessTokenHash(accessToken string) string {
	sum := sha256.Sum256([]byte(accessToken))

	return base64.RawURLEncoding.EncodeToString(sum[:len(sum)/2])
}

func sameString(held, want string) bool {
	return held != "" && subtle.ConstantTimeCompare([]byte(held), []byte(want)) == 1
}

func (c *Client) UserInfo(ctx context.Context, token *Token) (*Identity, error) {
	endpoint, err := c.Issuer.endpoint("userinfo_endpoint", c.Issuer.Metadata.UserinfoEndpoint)
	if err != nil {
		return nil, err
	}

	if token == nil || token.AccessToken == "" {
		return nil, &InvalidToken{Code: "invalid_token", Description: "userinfo needs an access token"}
	}

	transport := &Transport{
		Source:  TokenSourceFunc(func(context.Context) (*Token, error) { return token, nil }),
		Key:     c.DPoP,
		Base:    c.Issuer.settings.client.Transport,
		Origins: []string{endpoint},
	}

	request, err := http.NewRequestWithContext(ctx, http.MethodGet, endpoint, nil)
	if err != nil {
		return nil, err
	}

	request.Header.Set("Accept", "application/json")

	client := &http.Client{Transport: transport, Timeout: c.Issuer.settings.client.Timeout}

	response, err := client.Do(request)
	if err != nil {
		return nil, err
	}

	held := &Identity{}

	if err := decoded(response, held); err != nil {
		return nil, err
	}

	if held.Subject == "" {
		return nil, &Refused{Code: "server_error", Description: "userinfo answered without a subject"}
	}

	return held, nil
}

const BackchannelLogoutEvent = "http://schemas.openid.net/event/backchannel-logout"

type LogoutToken struct {
	jwt.Claims

	SessionID string                     `json:"sid,omitempty"`
	Events    map[string]json.RawMessage `json:"events"`
	Nonce     *string                    `json:"nonce,omitempty"`
}

func (c *Client) VerifyLogoutToken(ctx context.Context, raw string) (*LogoutToken, error) {
	held := &LogoutToken{}

	if err := c.Issuer.verified(ctx, raw, []string{"logout+jwt"}, held); err != nil {
		return nil, err
	}

	if held.ID == "" || held.IssuedAt == nil || held.Expiry == nil {
		return nil, invalid("missing_claims", "jti, iat, and exp")
	}

	expected := jwt.Expected{Issuer: c.Issuer.URL, AnyAudience: jwt.Audience{c.ID}, Time: time.Now()}

	if err := held.ValidateWithLeeway(expected, time.Minute); err != nil {
		return nil, unverified(err)
	}

	switch event, found := held.Events[BackchannelLogoutEvent]; {
	case held.Nonce != nil:
		return nil, invalid("logout_with_nonce")
	case held.Subject == "" && held.SessionID == "":
		return nil, invalid("logout_names_nobody")
	case !found || len(event) == 0 || event[0] != '{':
		return nil, invalid("not_a_logout")
	}

	return held, nil
}
