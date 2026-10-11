package masks

import (
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"net/url"
	"strings"
	"time"

	"github.com/go-jose/go-jose/v4/jwt"
)

const (
	DPoP      = "DPoP"
	proofType = "dpop+jwt"
)

type proofClaims struct {
	ID       string `json:"jti"`
	Method   string `json:"htm"`
	Target   string `json:"htu"`
	IssuedAt int64  `json:"iat"`
	Hash     string `json:"ath,omitempty"`
	Nonce    string `json:"nonce,omitempty"`
}

func (k *Key) Proof(method, target, accessToken, nonce string) (string, error) {
	held, err := url.Parse(target)
	if err != nil {
		return "", err
	}

	return k.proof(method, held, accessToken, nonce)
}

func (k *Key) proof(method string, target *url.URL, accessToken, nonce string) (string, error) {
	claims := proofClaims{
		ID:       rand.Text(),
		Method:   strings.ToUpper(method),
		Target:   htu(target),
		IssuedAt: time.Now().Unix(),
		Nonce:    nonce,
	}

	if accessToken != "" {
		claims.Hash = tokenHash(accessToken)
	}

	return jwt.Signed(k.prover).Claims(claims).Serialize()
}

func tokenHash(accessToken string) string {
	sum := sha256.Sum256([]byte(accessToken))

	return base64.RawURLEncoding.EncodeToString(sum[:])
}
