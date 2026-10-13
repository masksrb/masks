package redisstore

import (
	"context"
	"crypto/rand"
	"errors"
	"os"
	"testing"
	"time"

	"github.com/redis/go-redis/v9"
)

func newStore(t *testing.T) (*Store, string) {
	t.Helper()

	address := os.Getenv("REDIS_URL")
	if address == "" {
		t.Skip("REDIS_URL names no Redis to test against")
	}

	options, err := redis.ParseURL(address)
	if err != nil {
		t.Fatal(err)
	}

	client := redis.NewClient(options)
	t.Cleanup(func() { client.Close() })

	return New(client), "masks:test:" + rand.Text() + ":"
}

func TestAKeyIsAddedOnlyOnce(t *testing.T) {
	store, prefix := newStore(t)
	ctx := context.Background()

	first, err := store.Add(ctx, prefix+"proof", []byte{1}, time.Minute)
	if err != nil || !first {
		t.Fatalf("the first add answered %v, %v", first, err)
	}

	again, err := store.Add(ctx, prefix+"proof", []byte{2}, time.Minute)
	if err != nil || again {
		t.Fatalf("the second add answered %v, %v", again, err)
	}

	if held, _ := store.Get(ctx, prefix+"proof"); string(held) != "\x01" {
		t.Fatalf("the second add replaced the value with %q", held)
	}
}

func TestAMissingKeyIsNil(t *testing.T) {
	store, prefix := newStore(t)

	held, err := store.Get(context.Background(), prefix+"nothing")
	if err != nil || held != nil {
		t.Fatalf("a missing key answered %q, %v", held, err)
	}
}

func TestAValueIsSetReadAndDeleted(t *testing.T) {
	store, prefix := newStore(t)
	ctx := context.Background()

	if err := store.Set(ctx, prefix+"session", []byte("sealed"), time.Hour); err != nil {
		t.Fatal(err)
	}

	if err := store.Set(ctx, prefix+"session", []byte("sealed again"), time.Hour); err != nil {
		t.Fatal(err)
	}

	if held, err := store.Get(ctx, prefix+"session"); err != nil || string(held) != "sealed again" {
		t.Fatalf("the value read back as %q, %v", held, err)
	}

	if err := store.Delete(ctx, prefix+"session"); err != nil {
		t.Fatal(err)
	}

	if held, _ := store.Get(ctx, prefix+"session"); held != nil {
		t.Fatalf("a deleted value read back as %q", held)
	}
}

func TestAValueExpires(t *testing.T) {
	store, prefix := newStore(t)
	ctx := context.Background()

	if _, err := store.Add(ctx, prefix+"logout", []byte{1}, 100*time.Millisecond); err != nil {
		t.Fatal(err)
	}

	if err := store.Set(ctx, prefix+"departed", []byte("1"), 0); err != nil {
		t.Fatal(err)
	}

	time.Sleep(200 * time.Millisecond)

	if held, _ := store.Get(ctx, prefix+"logout"); held != nil {
		t.Fatal("an added key outlived its expiry")
	}

	if held, _ := store.Get(ctx, prefix+"departed"); held != nil {
		t.Fatal("a key set to expire at once was kept for good")
	}
}

func TestAnUnreachableRedisIsAnError(t *testing.T) {
	_, prefix := newStore(t)
	client := redis.NewClient(&redis.Options{Addr: "127.0.0.1:1", MaxRetries: -1})
	t.Cleanup(func() { client.Close() })
	store := New(client)

	if _, err := store.Add(context.Background(), prefix+"proof", []byte{1}, time.Minute); err == nil {
		t.Fatal("an add to a closed server succeeded")
	}

	if _, err := store.Get(context.Background(), prefix+"proof"); err == nil || errors.Is(err, redis.Nil) {
		t.Fatalf("a read from a closed server answered %v", err)
	}
}
