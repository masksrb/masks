package masks

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/url"
	"strings"
	"sync"
	"time"

	"github.com/go-jose/go-jose/v4"
)

const (
	discoveryPath = "/.well-known/openid-configuration"
	resourcePath  = "/.well-known/oauth-protected-resource"
	keysLifetime  = 5 * time.Minute
	keysPatience  = 30 * time.Second
)

type Tenant struct {
	UUID      string `json:"uuid"`
	Subdomain string `json:"subdomain"`
	Name      string `json:"name"`
}

type Metadata struct {
	Issuer                            string   `json:"issuer"`
	Tenant                            Tenant   `json:"tenant"`
	AuthorizationEndpoint             string   `json:"authorization_endpoint"`
	TokenEndpoint                     string   `json:"token_endpoint"`
	UserinfoEndpoint                  string   `json:"userinfo_endpoint"`
	JWKSURI                           string   `json:"jwks_uri"`
	RegistrationEndpoint              string   `json:"registration_endpoint"`
	DeviceAuthorizationEndpoint       string   `json:"device_authorization_endpoint"`
	HandshakeEndpoint                 string   `json:"handshake_endpoint"`
	RevocationEndpoint                string   `json:"revocation_endpoint"`
	IntrospectionEndpoint             string   `json:"introspection_endpoint"`
	EndSessionEndpoint                string   `json:"end_session_endpoint"`
	ScopesSupported                   []string `json:"scopes_supported"`
	GrantTypesSupported               []string `json:"grant_types_supported"`
	TokenEndpointAuthMethodsSupported []string `json:"token_endpoint_auth_methods_supported"`
	DPoPSigningAlgValuesSupported     []string `json:"dpop_signing_alg_values_supported"`
}

type ResourceMetadata struct {
	Resource               string   `json:"resource"`
	AuthorizationServers   []string `json:"authorization_servers"`
	ScopesSupported        []string `json:"scopes_supported"`
	BearerMethodsSupported []string `json:"bearer_methods_supported"`
	ResourceName           string   `json:"resource_name"`
}

type Option func(*settings)

type settings struct {
	client    *http.Client
	plainHTTP bool
}

func WithHTTPClient(client *http.Client) Option {
	return func(held *settings) { held.client = client }
}

func AllowPlainHTTP() Option {
	return func(held *settings) { held.plainHTTP = true }
}

type Issuer struct {
	URL      string
	Metadata Metadata

	settings settings
	keysLock sync.Mutex
	keys     jose.JSONWebKeySet
	keysAt   time.Time
}

func Discover(ctx context.Context, issuer string, options ...Option) (*Issuer, error) {
	held := settled(options)
	named := strings.TrimSuffix(issuer, "/")

	if err := held.check(named); err != nil {
		return nil, err
	}

	found := &Issuer{URL: named, settings: held}

	if err := found.get(ctx, named+discoveryPath, "", &found.Metadata); err != nil {
		return nil, err
	}

	if strings.TrimSuffix(found.Metadata.Issuer, "/") != named {
		return nil, fmt.Errorf("masks: %s publishes a document naming %q", named, found.Metadata.Issuer)
	}

	for _, endpoint := range found.endpoints() {
		if err := found.settings.check(endpoint); err != nil {
			return nil, err
		}
	}

	return found, nil
}

func DiscoverResource(ctx context.Context, resource string, options ...Option) (*ResourceMetadata, error) {
	held := settled(options)
	named := strings.TrimSuffix(resource, "/")

	if err := held.check(named); err != nil {
		return nil, err
	}

	parsed, err := url.Parse(named)
	if err != nil {
		return nil, err
	}

	document := *parsed
	document.Path = resourcePath + parsed.Path

	found := &ResourceMetadata{}
	asker := &Issuer{settings: held}

	if err := asker.get(ctx, document.String(), "", found); err != nil {
		return nil, err
	}

	if strings.TrimSuffix(found.Resource, "/") != named {
		return nil, fmt.Errorf("masks: %s publishes metadata naming %q", named, found.Resource)
	}

	return found, nil
}

func settled(options []Option) settings {
	held := settings{client: &http.Client{Timeout: 30 * time.Second}}

	for _, option := range options {
		option(&held)
	}

	return held
}

func (s settings) check(target string) error {
	parsed, err := url.Parse(target)
	if err != nil {
		return err
	}

	switch {
	case parsed.Scheme == "https" && parsed.Host != "":
		return nil
	case parsed.Scheme == "http" && (s.plainHTTP || loopback(parsed.Hostname())):
		return nil
	case parsed.Scheme == "http":
		return fmt.Errorf("%w: %s", ErrInsecure, parsed.Redacted())
	default:
		return fmt.Errorf("masks: %q is not an http or https URL", target)
	}
}

func loopback(host string) bool {
	if host == "localhost" || strings.HasSuffix(host, ".localhost") {
		return true
	}

	ip := net.ParseIP(host)

	return ip != nil && ip.IsLoopback()
}

func (i *Issuer) endpoints() []string {
	held := i.Metadata

	return nonEmpty(
		held.AuthorizationEndpoint, held.TokenEndpoint, held.UserinfoEndpoint, held.JWKSURI,
		held.RegistrationEndpoint, held.DeviceAuthorizationEndpoint, held.HandshakeEndpoint,
		held.RevocationEndpoint, held.IntrospectionEndpoint, held.EndSessionEndpoint,
	)
}

func nonEmpty(values ...string) []string {
	held := values[:0]

	for _, value := range values {
		if value != "" {
			held = append(held, value)
		}
	}

	return held
}

func (i *Issuer) endpoint(named, value string) (string, error) {
	if value == "" {
		return "", fmt.Errorf("masks: %s publishes no %s", i.URL, named)
	}

	return value, nil
}

func (i *Issuer) sameOrigin(target string) error {
	want, err := url.Parse(i.URL)
	if err != nil {
		return err
	}

	held, err := url.Parse(target)
	if err != nil {
		return err
	}

	if !strings.EqualFold(held.Scheme, want.Scheme) || !strings.EqualFold(held.Host, want.Host) {
		return fmt.Errorf("%w: %s", ErrForeign, held.Redacted())
	}

	return nil
}

func (i *Issuer) key(ctx context.Context, kid string) (*jose.JSONWebKey, error) {
	i.keysLock.Lock()
	defer i.keysLock.Unlock()

	age := time.Since(i.keysAt)

	if found := i.keys.Key(kid); len(found) > 0 && age < keysLifetime {
		return &found[0], nil
	}

	if age >= keysPatience {
		var fetched jose.JSONWebKeySet

		if err := i.get(ctx, i.Metadata.JWKSURI, "", &fetched); err != nil {
			return nil, err
		}

		i.keys = fetched
		i.keysAt = time.Now()
	}

	if found := i.keys.Key(kid); len(found) > 0 {
		return &found[0], nil
	}

	return nil, fmt.Errorf("%w: %s publishes no key %q", ErrInvalidToken, i.URL, kid)
}

func (i *Issuer) get(ctx context.Context, target, bearer string, into any) error {
	return i.send(ctx, http.MethodGet, target, bearer, nil, into)
}

func (i *Issuer) send(ctx context.Context, method, target, bearer string, body any, into any) error {
	var reader io.Reader

	if body != nil {
		encoded, err := json.Marshal(body)
		if err != nil {
			return err
		}

		reader = bytes.NewReader(encoded)
	}

	request, err := http.NewRequestWithContext(ctx, method, target, reader)
	if err != nil {
		return err
	}

	request.Header.Set("Accept", "application/json")

	if body != nil {
		request.Header.Set("Content-Type", "application/json")
	}

	if bearer != "" {
		request.Header.Set("Authorization", "Bearer "+bearer)
	}

	return i.do(request, into)
}

func (i *Issuer) do(request *http.Request, into any) error {
	response, err := i.settings.client.Do(request)
	if err != nil {
		return err
	}
	defer response.Body.Close()

	if response.StatusCode >= 300 {
		return refused(response)
	}

	if into == nil || response.StatusCode == http.StatusNoContent {
		return nil
	}

	if err := json.NewDecoder(io.LimitReader(response.Body, readLimit)).Decode(into); err != nil {
		return errors.Join(fmt.Errorf("masks: %s answered with something other than JSON", request.URL.Redacted()), err)
	}

	return nil
}
