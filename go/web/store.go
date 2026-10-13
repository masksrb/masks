package web

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"slices"
	"strings"
	"time"
)

type Store interface {
	Add(ctx context.Context, key string, value []byte, expiresIn time.Duration) (bool, error)
	Get(ctx context.Context, key string) ([]byte, error)
	Set(ctx context.Context, key string, value []byte, expiresIn time.Duration) error
	Delete(ctx context.Context, key string) error
}

type MemoryStore struct {
	entries expiring[[]byte]
}

func (m *MemoryStore) Add(_ context.Context, key string, value []byte, expiresIn time.Duration) (bool, error) {
	return m.entries.add(key, slices.Clone(value), expiresIn), nil
}

func (m *MemoryStore) Get(_ context.Context, key string) ([]byte, error) {
	held, _ := m.entries.get(key)

	return slices.Clone(held), nil
}

func (m *MemoryStore) Set(_ context.Context, key string, value []byte, expiresIn time.Duration) error {
	kept := slices.Clone(value)
	m.entries.set(key, expiresIn, func([]byte, bool) []byte { return kept })

	return nil
}

func (m *MemoryStore) Delete(_ context.Context, key string) error {
	m.entries.delete(key)

	return nil
}

func keyed(parts ...string) string {
	sum := sha256.Sum256([]byte(strings.Join(parts, "\x00")))

	return "masks:" + hex.EncodeToString(sum[:])
}
