package web

import (
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
	Issuer                  string    `json:"issuer,omitempty"`
	ClientID                string    `json:"client_id"`
	ClientSecret            string    `json:"client_secret,omitempty"`
	RegistrationAccessToken string    `json:"registration_access_token,omitempty"`
	RegistrationClientURI   string    `json:"registration_client_uri,omitempty"`
	ConnectedAt             time.Time `json:"connected_at,omitzero"`
}

func CredentialsFrom(issuer string, held *masks.Registration) *Credentials {
	return &Credentials{
		Issuer:                  issuer,
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
	path string
	lock sync.Mutex
	held *Credentials
	seen os.FileInfo
	read bool
}

func FileCredentials(path string) CredentialStore {
	return &fileCredentials{path: path}
}

func (f *fileCredentials) Load(*http.Request) (*Credentials, error) {
	f.lock.Lock()
	defer f.lock.Unlock()

	return f.current()
}

func (f *fileCredentials) current() (*Credentials, error) {
	info, err := os.Stat(f.path)
	if err != nil && !errors.Is(err, fs.ErrNotExist) {
		return nil, err
	}

	if f.read && unchanged(f.seen, info) {
		return f.held, nil
	}

	held, err := readCredentials(f.path)
	if err != nil {
		return nil, err
	}

	f.held, f.seen, f.read = held, info, true

	return held, nil
}

func unchanged(seen, info os.FileInfo) bool {
	if seen == nil || info == nil {
		return seen == nil && info == nil
	}

	return os.SameFile(seen, info) && seen.ModTime().Equal(info.ModTime()) && seen.Size() == info.Size()
}

func readCredentials(path string) (*Credentials, error) {
	data, err := os.ReadFile(path)

	switch {
	case errors.Is(err, fs.ErrNotExist):
		return nil, nil
	case err != nil:
		return nil, err
	}

	held := &Credentials{}

	if err := json.Unmarshal(data, held); err != nil || held.ClientID == "" {
		return nil, nil
	}

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

	f.read = false

	return nil
}

func (f *fileCredentials) Forget(*http.Request) error {
	f.lock.Lock()
	defer f.lock.Unlock()

	known := f.held

	held, err := f.current()
	if err != nil {
		return err
	}

	if held == nil || (known != nil && held.ClientID != known.ClientID) {
		return nil
	}

	if err := os.Remove(f.path); err != nil && !errors.Is(err, fs.ErrNotExist) {
		return err
	}

	f.held, f.seen = nil, nil

	return nil
}
