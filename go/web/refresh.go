package web

import (
	"context"
	"crypto/aes"
	"crypto/cipher"
	"crypto/hkdf"
	"crypto/rand"
	"crypto/sha256"
	"encoding/json"
	"errors"
	"net/http"
	"strconv"
	"sync"
	"time"

	masks "github.com/masksrb/masks/go"
)

const (
	refreshTimeout = 30 * time.Second
	renewalMemory  = time.Minute
	renewalClaim   = 30 * time.Second
	renewalWait    = 50 * time.Millisecond
	logoutMemory   = 10 * time.Minute
)

type outcome string

const (
	renewed      outcome = "renewed"
	refused      outcome = "refused"
	unregistered outcome = "unregistered"
	unreachable  outcome = "unreachable"
)

type renewal struct {
	Outcome  outcome         `json:"outcome"`
	Token    *masks.Token    `json:"token,omitempty"`
	Identity *masks.Identity `json:"identity,omitempty"`
}

func (a *App) renew(ctx context.Context, s *site, data *session) *renewal {
	return a.flights.do(s.issuer.URL+" "+data.Token.RefreshToken, func() *renewal {
		ctx, cancel := context.WithTimeout(context.WithoutCancel(ctx), refreshTimeout)
		defer cancel()

		return a.shared(ctx, s, data)
	})
}

func (a *App) shared(ctx context.Context, s *site, data *session) *renewal {
	spent := data.Token.RefreshToken
	result := keyed("refreshed", s.issuer.URL, spent)
	claim := keyed("refreshing", s.issuer.URL, spent)
	store := a.config.Store

	if found := opened(ctx, store, result, spent); found != nil {
		return found
	}

	claimed, err := store.Add(ctx, claim, []byte{1}, renewalClaim)
	if err != nil {
		return &renewal{Outcome: unreachable}
	}

	if !claimed {
		return awaited(ctx, store, result, claim, spent)
	}

	defer store.Delete(context.WithoutCancel(ctx), claim)

	held := a.refresh(ctx, s, data)

	if held.Outcome != unreachable {
		if sealed, err := sealRenewal(spent, held); err == nil {
			_ = store.Set(ctx, result, sealed, renewalMemory)
		}
	}

	return held
}

func awaited(ctx context.Context, store Store, result, claim, spent string) *renewal {
	for {
		select {
		case <-ctx.Done():
			return &renewal{Outcome: unreachable}
		case <-time.After(renewalWait):
		}

		if found := opened(ctx, store, result, spent); found != nil {
			return found
		}

		if pending, err := store.Get(ctx, claim); err != nil || pending == nil {
			return &renewal{Outcome: unreachable}
		}
	}
}

func (a *App) refresh(ctx context.Context, s *site, data *session) *renewal {
	client := a.signIn(s)

	token, err := client.Refresh(ctx, data.Token.RefreshToken, masks.TokenRequest{Resource: []string{s.resource}})

	var refusal *masks.Error

	switch {
	case errors.As(err, &refusal) && refusal.Code == "invalid_client":
		return &renewal{Outcome: unregistered}
	case errors.As(err, &refusal) && refusal.Status < http.StatusInternalServerError && refusal.Status != http.StatusTooManyRequests:
		return &renewal{Outcome: refused}
	case err != nil:
		return &renewal{Outcome: unreachable}
	}

	if token.RefreshToken == "" {
		token.RefreshToken = data.Token.RefreshToken
	}

	token.IDToken = ""
	identity := data.Identity

	if profile, err := client.UserInfo(ctx, token); err == nil && identity != nil && profile.Subject == identity.Subject {
		if merged, err := identity.Merged(profile, identityClaims...); err == nil {
			identity = merged
		}
	}

	return &renewal{Outcome: renewed, Token: token, Identity: identity}
}

func renewalCipher(refreshToken string) (cipher.AEAD, error) {
	derived, err := hkdf.Key(sha256.New, []byte(refreshToken), []byte("masks"), "masks/web shared refresh", 32)
	if err != nil {
		return nil, err
	}

	block, err := aes.NewCipher(derived)
	if err != nil {
		return nil, err
	}

	return cipher.NewGCM(block)
}

func sealRenewal(refreshToken string, held *renewal) ([]byte, error) {
	aead, err := renewalCipher(refreshToken)
	if err != nil {
		return nil, err
	}

	plain, err := json.Marshal(held)
	if err != nil {
		return nil, err
	}

	nonce := make([]byte, aead.NonceSize())
	rand.Read(nonce)

	return aead.Seal(nonce, nonce, plain, nil), nil
}

func opened(ctx context.Context, store Store, result, refreshToken string) *renewal {
	sealed, err := store.Get(ctx, result)
	if err != nil || sealed == nil {
		return nil
	}

	aead, err := renewalCipher(refreshToken)
	if err != nil || len(sealed) < aead.NonceSize() {
		return &renewal{Outcome: unreachable}
	}

	plain, err := aead.Open(nil, sealed[:aead.NonceSize()], sealed[aead.NonceSize():], nil)
	if err != nil {
		return &renewal{Outcome: unreachable}
	}

	held := &renewal{}

	if json.Unmarshal(plain, held) != nil || (held.Outcome == renewed && held.Token == nil) {
		return &renewal{Outcome: unreachable}
	}

	return held
}

type flights struct {
	lock sync.Mutex
	held map[string]*flight
}

type flight struct {
	done   chan struct{}
	result *renewal
}

func (f *flights) do(key string, run func() *renewal) *renewal {
	f.lock.Lock()

	if f.held == nil {
		f.held = map[string]*flight{}
	}

	if held, found := f.held[key]; found {
		f.lock.Unlock()
		<-held.done

		return held.result
	}

	held := &flight{done: make(chan struct{}), result: &renewal{Outcome: unreachable}}
	f.held[key] = held
	f.lock.Unlock()

	defer func() {
		f.lock.Lock()
		delete(f.held, key)
		f.lock.Unlock()
		close(held.done)
	}()

	held.result = run()

	return held.result
}

func (a *App) departed(ctx context.Context, issuer string, identity *masks.Identity, since int64) (bool, error) {
	if identity == nil {
		return false, nil
	}

	for _, named := range [][2]string{{"sid", identity.SessionID}, {"sub", identity.Subject}} {
		if named[1] == "" {
			continue
		}

		held, err := a.config.Store.Get(ctx, keyed("departed", issuer, named[0], named[1]))
		if err != nil {
			return false, err
		}

		if at, err := strconv.ParseInt(string(held), 10, 64); err == nil && at >= since {
			return true, nil
		}
	}

	return false, nil
}

func (a *App) depart(ctx context.Context, issuer string, logout *masks.LogoutToken) error {
	kind, value := "sid", logout.SessionID
	if value == "" {
		kind, value = "sub", logout.Subject
	}

	at := strconv.FormatInt(time.Now().UnixMilli(), 10)

	return a.config.Store.Set(ctx, keyed("departed", issuer, kind, value), []byte(at), a.config.SessionLifetime)
}

func (a *App) firstLogout(ctx context.Context, issuer string, logout *masks.LogoutToken) (bool, error) {
	memory := logoutMemory

	if logout.Expiry != nil {
		memory = max(memory, time.Until(logout.Expiry.Time())+time.Minute)
	}

	return a.config.Store.Add(ctx, keyed("logout", issuer, logout.ID), []byte{1}, memory)
}

func (a *App) replay() masks.ReplayStore {
	return masks.ReplayStoreFunc(func(ctx context.Context, key string, expiresIn time.Duration) (bool, error) {
		return a.config.Store.Add(ctx, keyed("proof", key), []byte{1}, expiresIn)
	})
}
