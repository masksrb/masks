package masks

import (
	"crypto/sha256"
	"encoding/base64"
	"net/url"
	"strings"
	"time"
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
	plain, err := withoutQuery(target)
	if err != nil {
		return "", err
	}

	claims := proofClaims{
		ID:       random(),
		Method:   strings.ToUpper(method),
		Target:   plain,
		IssuedAt: time.Now().Unix(),
		Nonce:    nonce,
	}

	if accessToken != "" {
		claims.Hash = tokenHash(accessToken)
	}

	return k.sign(proofType, claims, true)
}

func tokenHash(accessToken string) string {
	sum := sha256.Sum256([]byte(accessToken))

	return base64.RawURLEncoding.EncodeToString(sum[:])
}

func withoutQuery(target string) (string, error) {
	held, err := url.Parse(target)
	if err != nil {
		return "", err
	}

	held.RawQuery = ""
	held.ForceQuery = false
	held.Fragment = ""
	held.RawFragment = ""

	return held.String(), nil
}
