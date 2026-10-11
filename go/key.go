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

	thumbprint, err := public.Thumbprint(crypto.SHA256)
	if err != nil {
		return nil, err
	}

	public.KeyID = base64.RawURLEncoding.EncodeToString(thumbprint)

	return &Key{private: private, public: public}, nil
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

func (k *Key) sign(typ string, claims any, embed bool) (string, error) {
	options := (&jose.SignerOptions{EmbedJWK: embed}).WithType(jose.ContentType(typ))

	if !embed {
		options = options.WithHeader(jose.HeaderKey("kid"), k.public.KeyID)
	}

	signer, err := jose.NewSigner(jose.SigningKey{Algorithm: jose.ES256, Key: k.private}, options)
	if err != nil {
		return "", err
	}

	return jwt.Signed(signer).Claims(claims).Serialize()
}

func random() string {
	held := make([]byte, 24)
	_, _ = rand.Read(held)

	return base64.RawURLEncoding.EncodeToString(held)
}
