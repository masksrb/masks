package masks

import (
	"context"
	"sync"
	"time"
)

type ReplayStore interface {
	First(ctx context.Context, key string, expiresIn time.Duration) (bool, error)
}

type ReplayStoreFunc func(ctx context.Context, key string, expiresIn time.Duration) (bool, error)

func (f ReplayStoreFunc) First(ctx context.Context, key string, expiresIn time.Duration) (bool, error) {
	return f(ctx, key, expiresIn)
}

type MemoryReplayStore struct {
	lock  sync.Mutex
	held  map[string]time.Time
	swept time.Time
}

func (m *MemoryReplayStore) First(_ context.Context, key string, expiresIn time.Duration) (bool, error) {
	now := time.Now()

	m.lock.Lock()
	defer m.lock.Unlock()

	if m.held == nil {
		m.held = map[string]time.Time{}
	}

	if now.Sub(m.swept) > time.Second {
		for held, until := range m.held {
			if now.After(until) {
				delete(m.held, held)
			}
		}

		m.swept = now
	}

	if until, seen := m.held[key]; seen && !now.After(until) {
		return false, nil
	}

	m.held[key] = now.Add(expiresIn)

	return true, nil
}
