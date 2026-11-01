package masks

import (
	"context"
	"errors"
	"io"
	"net/http"
	"net/url"
	"slices"
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
	fetch func(ctx context.Context, held *Token) (*Token, error)
}

func ReuseTokenSource(held *Token, fetch TokenSourceFunc) TokenSource {
	return &reused{held: held, fetch: func(ctx context.Context, _ *Token) (*Token, error) {
		if fetch == nil {
			return nil, &Refused{Code: "invalid_token", Description: "the token expired and nothing can fetch another"}
		}

		return fetch(ctx)
	}}
}

func (r *reused) Token(ctx context.Context) (*Token, error) {
	r.lock.Lock()
	defer r.lock.Unlock()

	if r.held.Valid() {
		return r.held, nil
	}

	fetched, err := r.fetch(ctx, r.held)
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
	return &reused{held: held, fetch: func(ctx context.Context, current *Token) (*Token, error) {
		if current == nil || current.RefreshToken == "" {
			return nil, refuse("no_refresh_token")
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

		return renewed, nil
	}}
}

type Transport struct {
	Source  TokenSource
	Key     *Key
	Base    http.RoundTripper
	Origins []string

	nonces  nonces
	once    sync.Once
	allowed []string
}

func (c *Client) HTTPClient(source TokenSource, origins ...string) *http.Client {
	return &http.Client{Transport: &Transport{Source: source, Key: c.DPoP, Base: c.Issuer.settings.client.Transport, Origins: origins}}
}

func (t *Transport) RoundTrip(request *http.Request) (*http.Response, error) {
	if !t.allows(request.URL) {
		closeBody(request)
		return nil, foreign("tokens_only_for", strings.Join(t.Origins, ", "), origin(request.URL))
	}

	token, err := t.Source.Token(request.Context())
	if err != nil {
		closeBody(request)
		return nil, err
	}

	nonce := t.nonces.load(request.URL)

	signed, err := t.signed(request, token, nonce)
	if err != nil {
		closeBody(request)
		return nil, err
	}

	response, err := t.base().RoundTrip(signed)
	if err != nil || !token.Bound() {
		return response, err
	}

	wanted := t.nonces.learn(request.URL, response)

	if wanted == "" || wanted == nonce || response.StatusCode != http.StatusUnauthorized ||
		!strings.Contains(response.Header.Get("WWW-Authenticate"), "use_dpop_nonce") {
		return response, nil
	}

	rewound := request.Clone(request.Context())

	if request.Body != nil && request.Body != http.NoBody {
		if request.GetBody == nil {
			return response, nil
		}

		if rewound.Body, err = request.GetBody(); err != nil {
			return response, nil
		}
	}

	io.Copy(io.Discard, io.LimitReader(response.Body, readLimit))
	response.Body.Close()

	again, err := t.signed(rewound, token, wanted)
	if err != nil {
		return nil, err
	}

	return t.base().RoundTrip(again)
}

func (t *Transport) allows(target *url.URL) bool {
	t.once.Do(func() {
		for _, allowed := range t.Origins {
			if parsed, err := url.Parse(allowed); err == nil {
				t.allowed = append(t.allowed, origin(parsed))
			}
		}
	})

	return slices.Contains(t.allowed, origin(target))
}

func closeBody(request *http.Request) {
	if request.Body != nil {
		request.Body.Close()
	}
}

func (t *Transport) signed(request *http.Request, token *Token, nonce string) (*http.Request, error) {
	held := request.Clone(request.Context())

	if !token.Bound() {
		held.Header.Set("Authorization", "Bearer "+token.AccessToken)
		return held, nil
	}

	if t.Key == nil {
		return nil, errors.New("masks: a DPoP token needs the key it is held to")
	}

	proof, err := t.Key.proof(request.Method, request.URL, token.AccessToken, nonce)
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
