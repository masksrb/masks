package masks

import (
	"crypto"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"encoding/base64"
	"encoding/json"
	"errors"

	"github.com/go-jose/go-jose/v4"
	"github.com/go-jose/go-jose/v4/jwt"
)

type Key struct {
	private *ecdsa.PrivateKey
	public  jose.JSONWebKey
	prover  jose.Signer
	asserts jose.Signer
}

func GenerateKey() (*Key, error) {
	held, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		return nil, err
	}

	return keyFor(held)
}

func ParseKey(data []byte) (*Key, error) {
	var held jose.JSONWebKey

	if err := held.UnmarshalJSON(data); err != nil {
		return nil, err
	}

	private, ok := held.Key.(*ecdsa.PrivateKey)
	if !ok || private.Curve != elliptic.P256() {
		return nil, errors.New("masks: a key is a private P-256 key")
	}

	return keyFor(private)
}

func keyFor(private *ecdsa.PrivateKey) (*Key, error) {
	public := jose.JSONWebKey{Key: &private.PublicKey, Algorithm: string(jose.ES256), Use: "sig"}

	kid, err := thumbprint(public)
	if err != nil {
		return nil, err
	}

	public.KeyID = kid
	signing := jose.SigningKey{Algorithm: jose.ES256, Key: private}

	prover, err := jose.NewSigner(signing, (&jose.SignerOptions{EmbedJWK: true}).WithType(proofType))
	if err != nil {
		return nil, err
	}

	asserts, err := jose.NewSigner(signing, (&jose.SignerOptions{}).WithType("JWT").WithHeader("kid", kid))
	if err != nil {
		return nil, err
	}

	return &Key{private: private, public: public, prover: prover, asserts: asserts}, nil
}

func thumbprint(key jose.JSONWebKey) (string, error) {
	held, err := key.Thumbprint(crypto.SHA256)
	if err != nil {
		return "", err
	}

	return base64.RawURLEncoding.EncodeToString(held), nil
}

func (k *Key) MarshalJSON() ([]byte, error) {
	return jose.JSONWebKey{Key: k.private, KeyID: k.public.KeyID, Algorithm: k.public.Algorithm, Use: k.public.Use}.MarshalJSON()
}

func (k *Key) UnmarshalJSON(data []byte) error {
	held, err := ParseKey(data)
	if err != nil {
		return err
	}

	*k = *held

	return nil
}

func (k *Key) Thumbprint() string {
	return k.public.KeyID
}

func (k *Key) PublicJWK() json.RawMessage {
	held, _ := k.public.MarshalJSON()

	return held
}

func (k *Key) JWKS() json.RawMessage {
	held, _ := json.Marshal(jose.JSONWebKeySet{Keys: []jose.JSONWebKey{k.public}})

	return held
}

func (k *Key) assert(claims jwt.Claims) (string, error) {
	return jwt.Signed(k.asserts).Claims(claims).Serialize()
}
