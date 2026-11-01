package masks

import (
	"context"
	"errors"
	"strconv"
	"strings"
	"time"
)

const (
	GrantTokenExchange = "urn:ietf:params:oauth:grant-type:token-exchange"

	TokenTypeAccessToken         = "urn:ietf:params:oauth:token-type:access_token"
	TokenTypeIDToken             = "urn:ietf:params:oauth:token-type:id_token"
	TokenTypeUpstreamAccessToken = "urn:masks:params:oauth:token-type:upstream_access_token"
)

type ExchangeRequest struct {
	SubjectToken       string
	SubjectTokenType   string
	ActorToken         string
	ActorTokenType     string
	RequestedTokenType string
	Audience           []string
	Scope              []string
	Resource           []string
	Lifetime           time.Duration
}

func (c *Client) Exchange(ctx context.Context, asked ExchangeRequest) (*Token, error) {
	if asked.SubjectToken == "" {
		return nil, errors.New("masks: an exchange needs a subject token")
	}

	if asked.ActorTokenType != "" && asked.ActorToken == "" {
		return nil, errors.New("masks: an actor token type needs an actor token")
	}

	form := TokenRequest{Scope: asked.Scope, Resource: asked.Resource}.form()
	form.Set("grant_type", GrantTokenExchange)
	form.Set("subject_token", asked.SubjectToken)
	form.Set("subject_token_type", or(asked.SubjectTokenType, TokenTypeAccessToken))

	if asked.ActorToken != "" {
		form.Set("actor_token", asked.ActorToken)
		form.Set("actor_token_type", or(asked.ActorTokenType, TokenTypeAccessToken))
	}

	if asked.RequestedTokenType != "" {
		form.Set("requested_token_type", asked.RequestedTokenType)
	}

	for _, audience := range asked.Audience {
		form.Add("audience", audience)
	}

	if asked.Lifetime > 0 {
		form.Set("requested_lifetime", strconv.FormatInt(max(int64(asked.Lifetime/time.Second), 1), 10))
	}

	wanted := or(asked.RequestedTokenType, TokenTypeAccessToken)

	granted, err := c.grant(ctx, form, c.DPoP != nil && wanted != TokenTypeUpstreamAccessToken)
	if err != nil {
		return nil, err
	}

	if granted.IssuedTokenType != wanted {
		return nil, &Refused{Code: "server_error", Description: "the token endpoint issued " + or(granted.IssuedTokenType, "an unnamed type") + " for " + wanted}
	}

	return granted, nil
}

func or(value, fallback string) string {
	if strings.TrimSpace(value) == "" {
		return fallback
	}

	return value
}
