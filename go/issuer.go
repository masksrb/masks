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
	"sync/atomic"
	"time"

	"github.com/go-jose/go-jose/v4"
)

const (
	discoveryPath = "/.well-known/openid-configuration"
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
	EnrollmentEndpoint                string   `json:"enrollment_endpoint"`
	BackchannelLogoutSupported        bool     `json:"backchannel_logout_supported"`
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
	pause     time.Duration
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
	nonces   nonces
	keys     keyring
}

type keyring struct {
	lock       sync.RWMutex
	fetching   sync.Mutex
	refreshing atomic.Bool
	set        jose.JSONWebKeySet
	at         time.Time
}

type nonces struct {
	held sync.Map
}

func (n *nonces) load(target *url.URL) string {
	held, _ := n.held.Load(origin(target))
	nonce, _ := held.(string)

	return nonce
}

func (n *nonces) learn(target *url.URL, response *http.Response) string {
	wanted := response.Header.Get("DPoP-Nonce")
	if wanted != "" {
		n.held.Store(origin(target), wanted)
	}

	return wanted
}

func Discover(ctx context.Context, issuer string, options ...Option) (*Issuer, error) {
	held := settled(options)

	named, err := held.named(issuer)
	if err != nil {
		return nil, err
	}

	found := &Issuer{URL: named, settings: held}

	if err := held.send(ctx, http.MethodGet, named+discoveryPath, "", nil, &found.Metadata); err != nil {
		return nil, err
	}

	if strings.TrimSuffix(found.Metadata.Issuer, "/") != named {
		return nil, fmt.Errorf("masks: %s publishes a document naming %q", named, found.Metadata.Issuer)
	}

	metadata := found.Metadata

	for _, endpoint := range []string{
		metadata.AuthorizationEndpoint, metadata.TokenEndpoint, metadata.UserinfoEndpoint, metadata.JWKSURI,
		metadata.RegistrationEndpoint, metadata.DeviceAuthorizationEndpoint, metadata.HandshakeEndpoint,
		metadata.RevocationEndpoint, metadata.IntrospectionEndpoint, metadata.EndSessionEndpoint,
		metadata.EnrollmentEndpoint,
	} {
		if endpoint == "" {
			continue
		}

		if err := held.check(endpoint); err != nil {
			return nil, err
		}
	}

	return found, nil
}

func DiscoverResource(ctx context.Context, resource string, options ...Option) (*ResourceMetadata, error) {
	held := settled(options)

	named, err := held.named(resource)
	if err != nil {
		return nil, err
	}

	document, err := url.Parse(named)
	if err != nil {
		return nil, err
	}

	document.Path = ResourceMetadataPath + document.Path

	found := &ResourceMetadata{}

	if err := held.send(ctx, http.MethodGet, document.String(), "", nil, found); err != nil {
		return nil, err
	}

	if strings.TrimSuffix(found.Resource, "/") != named {
		return nil, fmt.Errorf("masks: %s publishes metadata naming %q", named, found.Resource)
	}

	return found, nil
}

func settled(options []Option) settings {
	held := settings{client: &http.Client{Timeout: 30 * time.Second}, pause: 5 * time.Second}

	for _, option := range options {
		option(&held)
	}

	return held
}

func (s settings) named(raw string) (string, error) {
	named := strings.TrimSuffix(raw, "/")

	return named, s.check(named)
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

	if origin(held) != origin(want) {
		return fmt.Errorf("%w: %s", ErrForeign, held.Redacted())
	}

	return nil
}

func (i *Issuer) key(ctx context.Context, kid string) (*jose.JSONWebKey, error) {
	ring := &i.keys

	ring.lock.RLock()
	found := ring.set.Key(kid)
	age := time.Since(ring.at)
	ring.lock.RUnlock()

	if len(found) > 0 {
		if age >= keysLifetime && ring.refreshing.CompareAndSwap(false, true) {
			go func() {
				defer ring.refreshing.Store(false)
				_ = i.refreshKeys(context.WithoutCancel(ctx))
			}()
		}

		return &found[0], nil
	}

	if err := i.refreshKeys(ctx); err != nil {
		return nil, err
	}

	ring.lock.RLock()
	found = ring.set.Key(kid)
	ring.lock.RUnlock()

	if len(found) > 0 {
		return &found[0], nil
	}

	return nil, invalid("%s publishes no key %q", i.URL, kid)
}

func (i *Issuer) refreshKeys(ctx context.Context) error {
	ring := &i.keys

	ring.fetching.Lock()
	defer ring.fetching.Unlock()

	ring.lock.RLock()
	recent := time.Since(ring.at) < keysPatience
	ring.lock.RUnlock()

	if recent {
		return nil
	}

	var fetched jose.JSONWebKeySet

	if err := i.settings.send(ctx, http.MethodGet, i.Metadata.JWKSURI, "", nil, &fetched); err != nil {
		return err
	}

	ring.lock.Lock()
	ring.set = fetched
	ring.at = time.Now()
	ring.lock.Unlock()

	return nil
}

func (s settings) send(ctx context.Context, method, target, bearer string, body any, into any) error {
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

	if body != nil {
		request.Header.Set("Content-Type", "application/json")
	}

	if bearer != "" {
		request.Header.Set("Authorization", "Bearer "+bearer)
	}

	response, err := s.do(request)
	if err != nil {
		return err
	}

	return decoded(response, into)
}

func (s settings) do(request *http.Request) (*http.Response, error) {
	request.Header.Set("Accept", "application/json")

	if request.Method == http.MethodGet && request.Header.Get("Authorization") == "" {
		return s.client.Do(request)
	}

	held := *s.client
	held.CheckRedirect = func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse }

	return held.Do(request)
}

func decoded(response *http.Response, into any) error {
	defer response.Body.Close()

	if response.StatusCode >= 300 {
		return refused(response)
	}

	if into == nil || response.StatusCode == http.StatusNoContent {
		return nil
	}

	if err := json.NewDecoder(io.LimitReader(response.Body, readLimit)).Decode(into); err != nil {
		return errors.Join(fmt.Errorf("masks: %s answered with something other than JSON", response.Request.URL.Redacted()), err)
	}

	return nil
}
