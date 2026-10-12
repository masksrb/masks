package masks

import (
	"context"
	"encoding/json"
	"net/url"
	"slices"
	"strings"
	"time"

	"github.com/go-jose/go-jose/v4/jwt"
)

type Introspection struct {
	jwt.Claims

	Active               bool            `json:"active"`
	Scope                string          `json:"scope,omitempty"`
	ClientID             string          `json:"client_id,omitempty"`
	Username             string          `json:"username,omitempty"`
	TokenType            string          `json:"token_type,omitempty"`
	Confirmation         *Confirmation   `json:"cnf,omitempty"`
	Organization         *Organization   `json:"org,omitempty"`
	Tenant               *Tenant         `json:"tenant,omitempty"`
	AuthorizationDetails json.RawMessage `json:"authorization_details,omitempty"`
}

func (i *Introspection) Scopes() []string {
	return strings.Fields(i.Scope)
}

func (i *Introspection) HasScope(scope string) bool {
	return i.Active && slices.Contains(i.Scopes(), scope)
}

func (i *Introspection) Bound() bool {
	return i.Confirmation != nil && i.Confirmation.Thumbprint != ""
}

func (c *Client) Introspect(ctx context.Context, token, hint string) (*Introspection, error) {
	endpoint, err := c.Issuer.endpoint("introspection_endpoint", c.Issuer.Metadata.IntrospectionEndpoint)
	if err != nil {
		return nil, err
	}

	form := url.Values{}
	form.Set("token", token)

	if hint != "" {
		form.Set("token_type_hint", hint)
	}

	held := &Introspection{}

	if err := c.post(ctx, endpoint, form, false, held); err != nil {
		return nil, err
	}

	if !held.Active || (held.Expiry != nil && time.Now().After(held.Expiry.Time())) {
		return &Introspection{}, nil
	}

	return held, nil
}
