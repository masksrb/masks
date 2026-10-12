package web

import (
	"sync"
	"time"
)

const sweepEvery = time.Second

type expiring[V any] struct {
	lock  sync.Mutex
	held  map[string]expiringEntry[V]
	swept time.Time
}

type expiringEntry[V any] struct {
	value V
	until time.Time
}

func (e *expiring[V]) get(key string) (V, bool) {
	e.lock.Lock()
	defer e.lock.Unlock()

	held, found := e.held[key]
	if !found || time.Now().After(held.until) {
		var none V
		return none, false
	}

	return held.value, true
}

func (e *expiring[V]) set(key string, expiresIn time.Duration, change func(held V, found bool) V) {
	e.lock.Lock()
	defer e.lock.Unlock()

	now := time.Now()

	if e.held == nil {
		e.held = map[string]expiringEntry[V]{}
	}

	if now.Sub(e.swept) > sweepEvery {
		for name, held := range e.held {
			if now.After(held.until) {
				delete(e.held, name)
			}
		}

		e.swept = now
	}

	held, found := e.held[key]
	found = found && !now.After(held.until)

	e.held[key] = expiringEntry[V]{value: change(held.value, found), until: now.Add(expiresIn)}
}

func (e *expiring[V]) delete(key string) {
	e.lock.Lock()
	defer e.lock.Unlock()

	delete(e.held, key)
}

func (e *expiring[V]) len() int {
	e.lock.Lock()
	defer e.lock.Unlock()

	return len(e.held)
}
