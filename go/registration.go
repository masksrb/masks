package masks

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
)

type ClientMetadata struct {
	Name                    string          `json:"client_name,omitempty"`
	RedirectURIs            []string        `json:"redirect_uris,omitempty"`
	GrantTypes              []string        `json:"grant_types,omitempty"`
	ResponseTypes           []string        `json:"response_types,omitempty"`
	Scope                   string          `json:"scope,omitempty"`
	TokenEndpointAuthMethod AuthMethod      `json:"token_endpoint_auth_method,omitempty"`
	ApplicationType         string          `json:"application_type,omitempty"`
	ClientURI               string          `json:"client_uri,omitempty"`
	LogoURI                 string          `json:"logo_uri,omitempty"`
	JWKS                    json.RawMessage `json:"jwks,omitempty"`
	JWKSURI                 string          `json:"jwks_uri,omitempty"`
	Resources               []string        `json:"resources,omitempty"`
	DPoPBoundAccessTokens   bool            `json:"dpop_bound_access_tokens,omitempty"`
	BackchannelLogoutURI    string          `json:"backchannel_logout_uri,omitempty"`
}

type Registration struct {
	ClientMetadata

	ClientID                string `json:"client_id"`
	ClientSecret            string `json:"client_secret,omitempty"`
	ClientSecretExpiresAt   int64  `json:"client_secret_expires_at,omitempty"`
	ClientIDIssuedAt        int64  `json:"client_id_issued_at,omitempty"`
	RegistrationAccessToken string `json:"registration_access_token,omitempty"`
	RegistrationClientURI   string `json:"registration_client_uri,omitempty"`
}

func (i *Issuer) Register(ctx context.Context, metadata ClientMetadata, initialAccessToken string) (*Registration, error) {
	endpoint := i.Metadata.RegistrationEndpoint

	if endpoint == "" && initialAccessToken != "" {
		endpoint = i.URL + "/register"
	}

	if endpoint == "" {
		return nil, &Error{Code: "access_denied", Description: i.URL + " registers no clients without an initial access token"}
	}

	held := &Registration{}

	if err := i.settings.send(ctx, http.MethodPost, endpoint, initialAccessToken, metadata, held); err != nil {
		return nil, err
	}

	if err := i.owned(held); err != nil {
		return nil, err
	}

	return held, nil
}

func (i *Issuer) ReadRegistration(ctx context.Context, held *Registration) (*Registration, error) {
	return i.manage(ctx, http.MethodGet, held, nil)
}

func (i *Issuer) UpdateRegistration(ctx context.Context, held *Registration, metadata ClientMetadata) (*Registration, error) {
	return i.manage(ctx, http.MethodPut, held, metadata)
}

func (i *Issuer) DeleteRegistration(ctx context.Context, held *Registration) error {
	_, err := i.manage(ctx, http.MethodDelete, held, nil)

	return err
}

func (i *Issuer) manage(ctx context.Context, method string, held *Registration, body any) (*Registration, error) {
	if err := i.owned(held); err != nil {
		return nil, err
	}

	fresh := &Registration{}

	if err := i.settings.send(ctx, method, held.RegistrationClientURI, held.RegistrationAccessToken, body, fresh); err != nil {
		return nil, err
	}

	return kept(held, fresh), nil
}

func (i *Issuer) owned(held *Registration) error {
	if held.ClientID == "" {
		return errors.New("masks: the registration names no client_id")
	}

	if held.RegistrationClientURI == "" || held.RegistrationAccessToken == "" {
		return errors.New("masks: the registration holds no registration_client_uri and registration_access_token")
	}

	return i.sameOrigin(held.RegistrationClientURI)
}

func kept(held, fresh *Registration) *Registration {
	if fresh.ClientSecret == "" {
		fresh.ClientSecret = held.ClientSecret
		fresh.ClientSecretExpiresAt = held.ClientSecretExpiresAt
	}

	if fresh.RegistrationAccessToken == "" {
		fresh.RegistrationAccessToken = held.RegistrationAccessToken
	}

	if fresh.RegistrationClientURI == "" {
		fresh.RegistrationClientURI = held.RegistrationClientURI
	}

	return fresh
}

func (i *Issuer) Client(held *Registration, key, dpop *Key) *Client {
	return &Client{
		Issuer: i,
		ID:     held.ClientID,
		Secret: held.ClientSecret,
		Method: held.TokenEndpointAuthMethod,
		Key:    key,
		DPoP:   dpop,
	}
}
