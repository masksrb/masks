package web

import (
	"context"
	"encoding/json"
	"errors"
	"io/fs"
	"net/http"
	"os"
	"path/filepath"
	"sync"
	"time"

	masks "github.com/masksrb/masks/go"
)

type Credentials struct {
	ClientID                string    `json:"client_id"`
	ClientSecret            string    `json:"client_secret,omitempty"`
	RegistrationAccessToken string    `json:"registration_access_token,omitempty"`
	RegistrationClientURI   string    `json:"registration_client_uri,omitempty"`
	ConnectedAt             time.Time `json:"connected_at,omitzero"`
}

func CredentialsFrom(held *masks.Registration) *Credentials {
	return &Credentials{
		ClientID:                held.ClientID,
		ClientSecret:            held.ClientSecret,
		RegistrationAccessToken: held.RegistrationAccessToken,
		RegistrationClientURI:   held.RegistrationClientURI,
		ConnectedAt:             time.Now().UTC().Truncate(time.Second),
	}
}

func (c *Credentials) Registration() *masks.Registration {
	return &masks.Registration{
		ClientMetadata:          masks.ClientMetadata{TokenEndpointAuthMethod: masks.ClientSecretBasic},
		ClientID:                c.ClientID,
		ClientSecret:            c.ClientSecret,
		RegistrationAccessToken: c.RegistrationAccessToken,
		RegistrationClientURI:   c.RegistrationClientURI,
	}
}

type CredentialStore interface {
	Load(r *http.Request) (*Credentials, error)
	Save(r *http.Request, held *Credentials) error
	Forget(r *http.Request) error
}

type WritableStore interface {
	Writable(r *http.Request) error
}

type fileCredentials struct {
	path   string
	lock   sync.Mutex
	held   *Credentials
	loaded bool
}

func FileCredentials(path string) CredentialStore {
	return &fileCredentials{path: path}
}

func (f *fileCredentials) Load(*http.Request) (*Credentials, error) {
	f.lock.Lock()
	defer f.lock.Unlock()

	if f.loaded {
		return f.held, nil
	}

	data, err := os.ReadFile(f.path)

	switch {
	case errors.Is(err, fs.ErrNotExist):
		f.held, f.loaded = nil, true
		return nil, nil
	case err != nil:
		return nil, err
	}

	held := &Credentials{}

	if err := json.Unmarshal(data, held); err != nil || held.ClientID == "" {
		f.held, f.loaded = nil, true
		return nil, nil
	}

	f.held, f.loaded = held, true

	return held, nil
}

func (f *fileCredentials) Writable(*http.Request) error {
	if err := os.MkdirAll(filepath.Dir(f.path), 0o700); err != nil {
		return err
	}

	probe, err := os.CreateTemp(filepath.Dir(f.path), ".masks-*.json")
	if err != nil {
		return err
	}

	probe.Close()

	return os.Remove(probe.Name())
}

func (f *fileCredentials) Save(_ *http.Request, held *Credentials) error {
	f.lock.Lock()
	defer f.lock.Unlock()

	data, err := json.MarshalIndent(held, "", "  ")
	if err != nil {
		return err
	}

	if err := os.MkdirAll(filepath.Dir(f.path), 0o700); err != nil {
		return err
	}

	written, err := os.CreateTemp(filepath.Dir(f.path), ".masks-*.json")
	if err != nil {
		return err
	}

	defer os.Remove(written.Name())

	if err := written.Chmod(0o600); err != nil {
		written.Close()
		return err
	}

	if _, err := written.Write(append(data, '\n')); err != nil {
		written.Close()
		return err
	}

	if err := written.Close(); err != nil {
		return err
	}

	if err := os.Rename(written.Name(), f.path); err != nil {
		return err
	}

	f.held, f.loaded = held, true

	return nil
}

func (f *fileCredentials) Forget(*http.Request) error {
	f.lock.Lock()
	defer f.lock.Unlock()

	f.held, f.loaded = nil, true

	if err := os.Remove(f.path); err != nil && !errors.Is(err, fs.ErrNotExist) {
		return err
	}

	return nil
}

type DepartureStore interface {
	Depart(ctx context.Context, key string, at time.Time, expiresIn time.Duration) error
	DepartedAt(ctx context.Context, key string) (time.Time, error)
}

type MemoryDepartures struct {
	lock sync.Mutex
	held map[string]memoryDeparture
}

type memoryDeparture struct {
	at    time.Time
	until time.Time
}

func (m *MemoryDepartures) Depart(_ context.Context, key string, at time.Time, expiresIn time.Duration) error {
	m.lock.Lock()
	defer m.lock.Unlock()

	if m.held == nil {
		m.held = map[string]memoryDeparture{}
	}

	now := time.Now()

	for name, held := range m.held {
		if now.After(held.until) {
			delete(m.held, name)
		}
	}

	if held, found := m.held[key]; !found || at.After(held.at) {
		m.held[key] = memoryDeparture{at: at, until: now.Add(expiresIn)}
	}

	return nil
}

func (m *MemoryDepartures) DepartedAt(_ context.Context, key string) (time.Time, error) {
	m.lock.Lock()
	defer m.lock.Unlock()

	held, found := m.held[key]
	if !found || time.Now().After(held.until) {
		return time.Time{}, nil
	}

	return held.at, nil
}
