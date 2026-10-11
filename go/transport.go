package masks

import (
	"context"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strings"
	"sync"
)

type TokenSource interface {
	Token(ctx context.Context) (*Token, error)
}

type TokenSourceFunc func(ctx context.Context) (*Token, error)

func (f TokenSourceFunc) Token(ctx context.Context) (*Token, error) {
	return f(ctx)
}

type reused struct {
	lock  sync.Mutex
	held  *Token
	fetch TokenSourceFunc
}

func ReuseTokenSource(held *Token, fetch TokenSourceFunc) TokenSource {
	return &reused{held: held, fetch: fetch}
}

func (r *reused) Token(ctx context.Context) (*Token, error) {
	r.lock.Lock()
	defer r.lock.Unlock()

	if r.held.Valid() {
		return r.held, nil
	}

	fetched, err := r.fetch(ctx)
	if err != nil {
		return nil, err
	}

	r.held = fetched

	return fetched, nil
}

func (c *Client) CredentialsSource(asked TokenRequest) TokenSource {
	return ReuseTokenSource(nil, func(ctx context.Context) (*Token, error) {
		return c.ClientCredentials(ctx, asked)
	})
}

func (c *Client) RefreshSource(held *Token, asked TokenRequest, keep func(*Token) error) TokenSource {
	current := held

	return ReuseTokenSource(held, func(ctx context.Context) (*Token, error) {
		if current == nil || current.RefreshToken == "" {
			return nil, &Error{Code: "invalid_grant", Description: "there is no refresh token to renew this session with"}
		}

		renewed, err := c.Refresh(ctx, current.RefreshToken, asked)
		if err != nil {
			return nil, err
		}

		if renewed.RefreshToken == "" {
			renewed.RefreshToken = current.RefreshToken
		}

		if keep != nil {
			if err := keep(renewed); err != nil {
				return nil, err
			}
		}

		current = renewed

		return renewed, nil
	})
}

type Transport struct {
	Source  TokenSource
	Key     *Key
	Base    http.RoundTripper
	Origins []string

	nonces sync.Map
}

func (c *Client) HTTPClient(source TokenSource, origins ...string) *http.Client {
	return &http.Client{Transport: &Transport{Source: source, Key: c.DPoP, Base: c.Issuer.settings.client.Transport, Origins: origins}}
}

func (t *Transport) RoundTrip(request *http.Request) (*http.Response, error) {
	origin := strings.ToLower(request.URL.Scheme + "://" + request.URL.Host)

	if !t.allows(origin) {
		closeBody(request)
		return nil, fmt.Errorf("%w: this transport holds tokens only for %s", ErrForeign, strings.Join(t.Origins, ", "))
	}

	token, err := t.Source.Token(request.Context())
	if err != nil {
		closeBody(request)
		return nil, err
	}

	nonce, _ := t.nonces.Load(origin)
	held, _ := nonce.(string)

	signed, err := t.signed(request, token, held, false)
	if err != nil {
		return nil, err
	}

	response, err := t.base().RoundTrip(signed)
	if err != nil || !token.Bound() {
		return response, err
	}

	wanted := response.Header.Get("DPoP-Nonce")
	if wanted == "" {
		return response, nil
	}

	t.nonces.Store(origin, wanted)

	if response.StatusCode != http.StatusUnauthorized || !strings.Contains(response.Header.Get("WWW-Authenticate"), "use_dpop_nonce") {
		return response, nil
	}

	if request.Body != nil && request.GetBody == nil {
		return response, nil
	}

	io.Copy(io.Discard, io.LimitReader(response.Body, readLimit))
	response.Body.Close()

	again, err := t.signed(request, token, wanted, true)
	if err != nil {
		return nil, err
	}

	return t.base().RoundTrip(again)
}

func (t *Transport) allows(origin string) bool {
	for _, allowed := range t.Origins {
		parsed, err := url.Parse(allowed)
		if err == nil && strings.EqualFold(parsed.Scheme+"://"+parsed.Host, origin) {
			return true
		}
	}

	return false
}

func closeBody(request *http.Request) {
	if request.Body != nil {
		request.Body.Close()
	}
}

func (t *Transport) signed(request *http.Request, token *Token, nonce string, again bool) (*http.Request, error) {
	held := request.Clone(request.Context())

	if again && request.GetBody != nil && request.Body != nil && request.Body != http.NoBody {
		body, err := request.GetBody()
		if err != nil {
			return nil, err
		}

		held.Body = body
	}

	if !token.Bound() {
		held.Header.Set("Authorization", "Bearer "+token.AccessToken)
		return held, nil
	}

	if t.Key == nil {
		return nil, errors.New("masks: a DPoP token needs the key it is held to")
	}

	proof, err := t.Key.Proof(request.Method, request.URL.String(), token.AccessToken, nonce)
	if err != nil {
		return nil, err
	}

	held.Header.Set("Authorization", DPoP+" "+token.AccessToken)
	held.Header.Set("DPoP", proof)

	return held, nil
}

func (t *Transport) base() http.RoundTripper {
	if t.Base != nil {
		return t.Base
	}

	return http.DefaultTransport
}
