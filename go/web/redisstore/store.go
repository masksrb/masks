package redisstore

import (
	"context"
	"errors"
	"time"

	"github.com/redis/go-redis/v9"

	"github.com/masksrb/masks/go/web"
)

type Store struct {
	client redis.UniversalClient
}

var _ web.Store = (*Store)(nil)

func New(client redis.UniversalClient) *Store {
	return &Store{client: client}
}

func (s *Store) Add(ctx context.Context, key string, value []byte, expiresIn time.Duration) (bool, error) {
	return s.client.SetNX(ctx, key, value, lasting(expiresIn)).Result()
}

func (s *Store) Get(ctx context.Context, key string) ([]byte, error) {
	held, err := s.client.Get(ctx, key).Bytes()
	if errors.Is(err, redis.Nil) {
		return nil, nil
	}

	return held, err
}

func (s *Store) Set(ctx context.Context, key string, value []byte, expiresIn time.Duration) error {
	return s.client.Set(ctx, key, value, lasting(expiresIn)).Err()
}

func (s *Store) Delete(ctx context.Context, key string) error {
	return s.client.Del(ctx, key).Err()
}

func lasting(expiresIn time.Duration) time.Duration {
	return max(expiresIn, time.Millisecond)
}
