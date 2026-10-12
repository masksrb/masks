package masks

import (
	"context"
	"errors"
	"net/url"
	"slices"
	"time"
)

const ScopeDelegate = "masks:delegate:"

var (
	ErrDelegationRefused     = errors.New("masks: the delegation was refused")
	ErrDelegationUnavailable = errors.New("masks: the delegation is unavailable for now")

	delegationRefusals = []string{
		"invalid_grant", "insufficient_scope", "invalid_target", "unauthorized_client", "access_denied",
		"login_required", "interaction_required", "consent_required", "invalid_scope",
	}
)

type Delegation struct {
	Connection   string `json:"connection"`
	Provider     string `json:"provider"`
	ProviderName string `json:"provider_name,omitempty"`
	Label        string `json:"label,omitempty"`
	Subject      string `json:"subject,omitempty"`
}

type Connected struct {
	Delegation

	Secret string
}

type Upstream struct {
	AccessToken string
	Scope       string
	Expiry      time.Time
	Secret      string
}

func (u *Upstream) Valid() bool {
	return u != nil && u.AccessToken != "" && time.Until(u.Expiry) > time.Minute
}

type DelegationError struct {
	Code        string
	Description string
	Secret      string
	Unavailable bool
	Err         error
}

func (e *DelegationError) Error() string {
	held := ErrDelegationRefused.Error()
	if e.Unavailable {
		held = ErrDelegationUnavailable.Error()
	}

	if e.Code != "" {
		held += ": " + e.Code
	}

	if e.Description != "" {
		held += ": " + e.Description
	}

	return held
}

func (e *DelegationError) Is(target error) bool {
	return (target == ErrDelegationUnavailable && e.Unavailable) || (target == ErrDelegationRefused && !e.Unavailable)
}

func (e *DelegationError) Unwrap() error {
	return e.Err
}

func (e *DelegationError) SignInAgain() bool {
	return e.Code == "login_required" || e.Code == "interaction_required"
}

func (c *Client) StartDelegation(provider string, asked AuthRequest) (*Authorization, error) {
	if provider == "" {
		return nil, errors.New("masks: a delegation names a provider")
	}

	asked.Scope = []string{ScopeOpenID, ScopeOfflineAccess, ScopeDelegate + provider}

	started, err := c.AuthCodeURL(asked)
	if err != nil {
		return nil, err
	}

	started.Provider = provider

	return started, nil
}

func (c *Client) FinishDelegation(ctx context.Context, returned url.Values, pending *Authorization) (*Connected, error) {
	if pending == nil || pending.Provider == "" {
		return nil, &DelegationError{Code: "invalid_state", Description: "that answer is not for a connection this client started"}
	}

	signed, err := c.Complete(ctx, returned, pending)
	if err != nil {
		return nil, delegationFailed(err, "")
	}

	found := slices.IndexFunc(signed.Token.Delegations, func(held Delegation) bool { return held.Provider == pending.Provider })

	if found < 0 {
		return nil, &DelegationError{Code: "access_denied", Description: "masks connected nothing for " + pending.Provider}
	}

	if signed.Token.RefreshToken == "" {
		return nil, &DelegationError{Code: "invalid_grant", Description: "masks issued no refresh token to keep the connection with"}
	}

	held := signed.Token.Delegations[found]

	if signed.Identity != nil && held.Subject != "" && held.Subject != signed.Identity.Subject {
		return nil, &DelegationError{Code: "access_denied", Description: "the connection belongs to someone other than the person who signed in"}
	}

	return &Connected{Delegation: held, Secret: signed.Token.RefreshToken}, nil
}

func (c *Client) UpstreamToken(ctx context.Context, secret, connection string) (*Upstream, error) {
	if secret == "" || connection == "" {
		return nil, errors.New("masks: an upstream token needs the connection and its secret")
	}

	refreshed, err := c.Refresh(ctx, secret, TokenRequest{})
	if err != nil {
		return nil, delegationFailed(err, "")
	}

	rotated := refreshed.RefreshToken
	if rotated == "" {
		rotated = secret
	}

	released, err := c.Exchange(ctx, ExchangeRequest{
		SubjectToken:       refreshed.AccessToken,
		RequestedTokenType: TokenTypeUpstreamAccessToken,
		Audience:           []string{connection},
	})
	if err != nil {
		return nil, delegationFailed(err, rotated)
	}

	return &Upstream{AccessToken: released.AccessToken, Scope: released.Scope, Expiry: released.Expiry, Secret: rotated}, nil
}

func delegationFailed(err error, secret string) error {
	var refused *Error

	if errors.Is(err, ErrInvalidToken) {
		return &DelegationError{Code: "invalid_token", Description: err.Error(), Secret: secret, Err: err}
	}

	if !errors.As(err, &refused) {
		return &DelegationError{Description: err.Error(), Secret: secret, Unavailable: true, Err: err}
	}

	unavailable := !slices.Contains(delegationRefusals, refused.Code) &&
		(refused.Code == "temporarily_unavailable" || refused.Status >= 500 || refused.Status == 429)

	return &DelegationError{Code: refused.Code, Description: refused.Description, Secret: secret, Unavailable: unavailable, Err: err}
}
