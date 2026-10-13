package web

import (
	"crypto/aes"
	"crypto/cipher"
	"crypto/hkdf"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/binary"
	"encoding/json"
	"errors"
	"fmt"
	"maps"
	"net/http"
	"net/url"
	"slices"
	"strconv"
	"strings"
	"time"

	masks "github.com/masksrb/masks/go"
)

const (
	sealVersion   = 1
	sealLabel     = "masks/web session"
	chunkSize     = 3800
	chunkLimit    = 8
	pendingLimit  = 5
	pendingTTL    = time.Hour
	handshakeTTL  = time.Hour
	stepUpWithin  = 5 * time.Minute
	restartWithin = time.Minute
)

var errSealed = errors.New("masks/web: that value was not sealed with this app's secret")

type sealer struct {
	aeads []cipher.AEAD
}

func newSealer(secret []byte, previous [][]byte) (*sealer, error) {
	held := &sealer{}

	for _, key := range append([][]byte{secret}, previous...) {
		if len(key) < 32 {
			return nil, errors.New("masks/web: a session secret is at least 32 random bytes")
		}

		derived, err := hkdf.Key(sha256.New, key, nil, sealLabel, 32)
		if err != nil {
			return nil, err
		}

		block, err := aes.NewCipher(derived)
		if err != nil {
			return nil, err
		}

		aead, err := cipher.NewGCM(block)
		if err != nil {
			return nil, err
		}

		held.aeads = append(held.aeads, aead)
	}

	return held, nil
}

func (s *sealer) seal(plain []byte, purpose string, expiry time.Time) string {
	aead := s.aeads[0]
	nonce := make([]byte, aead.NonceSize())
	rand.Read(nonce)

	stamped := binary.BigEndian.AppendUint64(nil, uint64(expiry.Unix()))
	stamped = append(stamped, plain...)

	sealed := append([]byte{sealVersion}, nonce...)
	sealed = aead.Seal(sealed, nonce, stamped, []byte(purpose))

	return base64.RawURLEncoding.EncodeToString(sealed)
}

func (s *sealer) open(text, purpose string) ([]byte, error) {
	sealed, err := base64.RawURLEncoding.DecodeString(text)
	if err != nil || len(sealed) < 1 || sealed[0] != sealVersion {
		return nil, errSealed
	}

	for _, aead := range s.aeads {
		size := aead.NonceSize()
		if len(sealed) < 1+size {
			return nil, errSealed
		}

		plain, err := aead.Open(nil, sealed[1:1+size], sealed[1+size:], []byte(purpose))
		if err != nil || len(plain) < 8 {
			continue
		}

		if time.Now().Unix() > int64(binary.BigEndian.Uint64(plain[:8])) {
			return nil, errSealed
		}

		return plain[8:], nil
	}

	return nil, errSealed
}

type pending struct {
	masks.Authorization

	ReturnTo string `json:"return_to,omitempty"`
	Expiry   int64  `json:"expiry"`
}

type steppedUp struct {
	Privileges []string `json:"privileges"`
	At         int64    `json:"at"`
}

type session struct {
	Issuer      string             `json:"issuer,omitempty"`
	Token       *masks.Token       `json:"token,omitempty"`
	Identity    *masks.Identity    `json:"identity,omitempty"`
	SignedInAt  int64              `json:"signed_in_at,omitempty"`
	Requests    map[string]pending `json:"requests,omitempty"`
	Handshakes  map[string]int64   `json:"handshakes,omitempty"`
	SteppedUp   *steppedUp         `json:"stepped_up,omitempty"`
	ReturnTo    string             `json:"return_to,omitempty"`
	RestartedAt int64              `json:"restarted_at,omitempty"`
	Farewell    string             `json:"farewell,omitempty"`

	FarewellUntil int64 `json:"farewell_until,omitempty"`
}

type state struct {
	data    *session
	id      string
	dirty   bool
	rotated bool
	present []string
}

func (s *state) change() *session {
	s.dirty = true

	return s.data
}

func (s *state) forget() {
	held := s.change()
	held.Token, held.Identity, held.SignedInAt, held.Issuer = nil, nil, 0, ""
}

func (s *state) renew(keep func(old *session) *session) {
	s.data = keep(s.data)
	s.dirty = true
	s.rotated = true
}

func (s *state) open(authorization *masks.Authorization, returnTo string) {
	held := s.change()
	now := time.Now()

	if held.Requests == nil {
		held.Requests = map[string]pending{}
	}

	held.Requests[authorization.State] = pending{Authorization: *authorization, ReturnTo: returnTo, Expiry: now.Add(pendingTTL).Unix()}
	held.Requests = newest(held.Requests, func(entry pending) int64 { return entry.Expiry }, now)
}

func (s *state) claim(id string) *pending {
	held, found := s.data.Requests[id]
	if id == "" || !found {
		return nil
	}

	delete(s.change().Requests, id)

	if time.Now().Unix() > held.Expiry {
		return nil
	}

	return &held
}

func (s *state) shake(id string) {
	held := s.change()
	now := time.Now()

	if held.Handshakes == nil {
		held.Handshakes = map[string]int64{}
	}

	held.Handshakes[id] = now.Add(handshakeTTL).Unix()
	held.Handshakes = newest(held.Handshakes, func(expiry int64) int64 { return expiry }, now)
}

func (s *state) shaken(id string) bool {
	expiry, found := s.data.Handshakes[id]
	if id == "" || !found {
		return false
	}

	delete(s.change().Handshakes, id)

	return time.Now().Unix() <= expiry
}

func newest[V any](held map[string]V, expiry func(V) int64, now time.Time) map[string]V {
	live := map[string]V{}

	for id, entry := range held {
		if expiry(entry) >= now.Unix() {
			live[id] = entry
		}
	}

	if len(live) <= pendingLimit {
		return live
	}

	ids := slices.SortedFunc(maps.Keys(live), func(a, b string) int { return int(expiry(live[b]) - expiry(live[a])) })

	for _, id := range ids[pendingLimit:] {
		delete(live, id)
	}

	return live
}

func (a *App) cookieName() string {
	if a.config.PlainHTTP {
		return "masks"
	}

	return "__Host-masks"
}

func (a *App) load(r *http.Request) (*state, error) {
	if held, ok := r.Context().Value(visitKey{a}).(*visit); ok {
		return held.state, nil
	}

	name := a.cookieName()
	held := &state{data: &session{}}

	text := ""

	for index := range chunkLimit {
		cookie, err := r.Cookie(chunkName(name, index))
		if err != nil {
			break
		}

		held.present = append(held.present, cookie.Name)
		text += cookie.Value
	}

	if text == "" {
		return held, nil
	}

	plain, err := a.sealer.open(text, name)
	if err != nil {
		held.dirty = true
		return held, nil
	}

	if a.config.Sessions != nil {
		held.id = string(plain)

		plain, err = a.config.Sessions.Get(r.Context(), keyed("session", held.id))
		if err != nil {
			return nil, err
		}

		if plain == nil {
			held.dirty = true
			return held, nil
		}

		if plain, err = a.sealer.open(string(plain), held.id); err != nil {
			held.dirty = true
			return held, nil
		}
	}

	if json.Unmarshal(plain, held.data) != nil {
		held.data = &session{}
		held.dirty = true
	}

	return held, nil
}

func (a *App) commit(w http.ResponseWriter, r *http.Request, held *state) error {
	if !held.dirty {
		return nil
	}

	held.dirty = false
	name := a.cookieName()
	expiry := time.Now().Add(a.config.SessionLifetime)
	empty := isEmpty(held.data)

	if a.config.Sessions != nil && held.id != "" && (held.rotated || empty) {
		if err := a.config.Sessions.Delete(r.Context(), keyed("session", held.id)); err != nil {
			return err
		}

		held.id = ""
	}

	held.rotated = false

	if empty {
		a.setChunks(w, held, name, nil, time.Time{})
		return nil
	}

	plain, err := json.Marshal(held.data)
	if err != nil {
		return err
	}

	value := ""

	if a.config.Sessions != nil {
		if held.id == "" {
			held.id = rand.Text() + rand.Text()
		}

		if err := a.config.Sessions.Set(r.Context(), keyed("session", held.id), []byte(a.sealer.seal(plain, held.id, expiry)), a.config.SessionLifetime); err != nil {
			return err
		}

		value = a.sealer.seal([]byte(held.id), name, expiry)
	} else {
		value = a.sealer.seal(plain, name, expiry)
	}

	var chunks []string

	for len(value) > chunkSize {
		chunks = append(chunks, value[:chunkSize])
		value = value[chunkSize:]
	}

	chunks = append(chunks, value)

	if len(chunks) > chunkLimit {
		return fmt.Errorf("masks/web: the session is %d bytes, too large for cookies; set Config.Sessions", len(plain))
	}

	a.setChunks(w, held, name, chunks, expiry)

	return nil
}

func (a *App) setChunks(w http.ResponseWriter, held *state, name string, chunks []string, expiry time.Time) {
	unset(w.Header(), name)

	written := map[string]bool{}

	for index, chunk := range chunks {
		cookie := a.cookie(chunkName(name, index), chunk)
		cookie.Expires = expiry
		cookie.MaxAge = int(time.Until(expiry).Seconds())
		http.SetCookie(w, cookie)
		written[cookie.Name] = true
	}

	for _, present := range held.present {
		if !written[present] {
			cookie := a.cookie(present, "")
			cookie.MaxAge = -1
			http.SetCookie(w, cookie)
		}
	}

	for name := range written {
		if !slices.Contains(held.present, name) {
			held.present = append(held.present, name)
		}
	}
}

func unset(header http.Header, name string) {
	var kept []string

	ours := chunkNames(name)

	for _, line := range header.Values("Set-Cookie") {
		if named, _, _ := strings.Cut(line, "="); !slices.Contains(ours, named) {
			kept = append(kept, line)
		}
	}

	if len(kept) == 0 {
		header.Del("Set-Cookie")
		return
	}

	header["Set-Cookie"] = kept
}

func chunkNames(name string) []string {
	names := make([]string, chunkLimit)

	for index := range chunkLimit {
		names[index] = chunkName(name, index)
	}

	return names
}

func (a *App) cookie(name, value string) *http.Cookie {
	return &http.Cookie{
		Name:     name,
		Value:    value,
		Path:     "/",
		HttpOnly: true,
		Secure:   !a.config.PlainHTTP,
		SameSite: http.SameSiteLaxMode,
	}
}

func chunkName(name string, index int) string {
	if index == 0 {
		return name
	}

	return name + "-" + strconv.Itoa(index)
}

func isEmpty(held *session) bool {
	return held.Token == nil && held.Identity == nil && len(held.Requests) == 0 && len(held.Handshakes) == 0 &&
		held.SteppedUp == nil && held.ReturnTo == "" && held.RestartedAt == 0 && held.Farewell == ""
}

func localPath(value string) string {
	if !strings.HasPrefix(value, "/") || strings.HasPrefix(value, "//") || strings.ContainsFunc(value, func(r rune) bool {
		return r <= 0x20 || r == 0x7f || r == '\\'
	}) {
		return ""
	}

	parsed, err := url.Parse(value)
	if err != nil || parsed.Scheme != "" || parsed.Host != "" || parsed.User != nil ||
		!strings.HasPrefix(parsed.Path, "/") || strings.HasPrefix(parsed.Path, "//") {
		return ""
	}

	return parsed.RequestURI()
}
