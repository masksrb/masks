package masks

import (
	"context"
	"crypto/rand"
	"fmt"
	"net/url"
	"strings"
)

var handshakeGrants = []string{GrantAuthorizationCode, GrantRefreshToken}

type Handshake struct {
	Issuer               *Issuer
	Name                 string
	Resource             string
	RedirectURIs         []string
	ReturnTo             string
	Scope                []string
	BackchannelLogoutURI string
}

func (h *Handshake) Start() (target, state string, err error) {
	if err := h.check(); err != nil {
		return "", "", err
	}

	endpoint := h.Issuer.Metadata.HandshakeEndpoint
	if endpoint == "" {
		endpoint = h.Issuer.URL + "/handshake"
	}

	parsed, err := url.Parse(endpoint)
	if err != nil {
		return "", "", err
	}

	state = rand.Text() + rand.Text()

	query := parsed.Query()
	query.Set("client_name", h.Name)
	query.Set("resource", h.Resource)
	query.Set("scope", strings.Join(h.Scope, " "))
	query.Set("return_to", h.ReturnTo)
	query.Set("state", state)
	query.Set("token_endpoint_auth_method", string(ClientSecretBasic))
	query["redirect_uris"] = h.RedirectURIs

	if h.BackchannelLogoutURI != "" {
		query.Set("backchannel_logout_uri", h.BackchannelLogoutURI)
	}

	parsed.RawQuery = query.Encode()

	return parsed.String(), state, nil
}

func (h *Handshake) Complete(ctx context.Context, returned url.Values, state string) (*Registration, error) {
	if !sameString(returned.Get("state"), state) {
		return nil, &Error{Code: "invalid_state", Description: "the handshake did not match this browser"}
	}

	if code := returned.Get("error"); code != "" {
		return nil, &Error{Code: code, Description: returned.Get("error_description")}
	}

	if named := strings.TrimSuffix(returned.Get("iss"), "/"); named != h.Issuer.URL {
		return nil, &Error{Code: "invalid_issuer", Description: fmt.Sprintf("the handshake came back from %q instead of %s", named, h.Issuer.URL)}
	}

	token := returned.Get("initial_access_token")
	if token == "" {
		return nil, &Error{Code: "invalid_request", Description: "the handshake came back without a token"}
	}

	return h.Issuer.Register(ctx, ClientMetadata{
		Name:                    h.Name,
		RedirectURIs:            h.RedirectURIs,
		GrantTypes:              handshakeGrants,
		Scope:                   strings.Join(h.Scope, " "),
		TokenEndpointAuthMethod: ClientSecretBasic,
		BackchannelLogoutURI:    h.BackchannelLogoutURI,
	}, token)
}

func (h *Handshake) check() error {
	if h.Issuer == nil {
		return fmt.Errorf("masks: a handshake needs an issuer")
	}

	resource, err := url.Parse(h.Resource)
	if err != nil || resource.Host == "" || resource.Fragment != "" {
		return fmt.Errorf("masks: a handshake needs an absolute resource URL, not %q", h.Resource)
	}

	if err := h.Issuer.settings.check(h.Resource); err != nil {
		return err
	}

	if len(h.Scope) == 0 || len(h.RedirectURIs) == 0 || h.ReturnTo == "" {
		return fmt.Errorf("masks: a handshake needs a scope, a redirect URI, and a return_to")
	}

	for _, held := range append([]string{h.ReturnTo, h.BackchannelLogoutURI}, h.RedirectURIs...) {
		if held == "" {
			continue
		}

		parsed, err := url.Parse(held)
		if err != nil || origin(parsed) != origin(resource) {
			return fmt.Errorf("%w: %s is not on %s", ErrForeign, held, origin(resource))
		}
	}

	return nil
}
