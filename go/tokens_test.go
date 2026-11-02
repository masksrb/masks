package masks

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"os"
	"strings"
	"testing"
	"time"

	"github.com/go-jose/go-jose/v4"
	"github.com/go-jose/go-jose/v4/jwt"
)

type tokenContract struct {
	ClientID  string                     `json:"client_id"`
	Resource  string                     `json:"resource"`
	Expecting tokenExpecting             `json:"expecting"`
	Secret    string                     `json:"secret"`
	Keys      map[string]json.RawMessage `json:"keys"`
	JWKS      json.RawMessage            `json:"jwks"`
	Discovery map[string]any             `json:"discovery"`
	Times     []string                   `json:"times"`
	Tokens    map[string]tokenShape      `json:"tokens"`
	Cases     []tokenCase                `json:"cases"`
}

type tokenExpecting struct {
	Nonce       *string `json:"nonce"`
	AccessToken *string `json:"access_token"`
	MaxAge      *int64  `json:"max_age"`
}

type tokenShape struct {
	Header map[string]any `json:"header"`
	Claims map[string]any `json:"claims"`
}

type tokenCase struct {
	Name      string          `json:"name"`
	Token     string          `json:"token"`
	Header    map[string]any  `json:"header"`
	Claims    map[string]any  `json:"claims"`
	Key       string          `json:"key"`
	Raw       *string         `json:"raw"`
	Expecting *tokenExpecting `json:"expecting"`
	Outcome   json.RawMessage `json:"outcome"`
}

type tokenOutcome struct {
	Failure string   `json:"failure"`
	Values  []string `json:"values"`
}

func readTokens(t *testing.T) tokenContract {
	t.Helper()

	body, err := os.ReadFile("../test/contract/tokens.json")
	if err != nil {
		t.Fatal(err)
	}

	var held tokenContract
	if err := json.Unmarshal(body, &held); err != nil {
		t.Fatal(err)
	}

	return held
}

func placed(value any, names map[string]string) any {
	switch held := value.(type) {
	case string:
		for name, replacement := range names {
			held = strings.ReplaceAll(held, "{"+name+"}", replacement)
		}

		return held
	case []any:
		out := make([]any, len(held))
		for index, item := range held {
			out[index] = placed(item, names)
		}

		return out
	case map[string]any:
		out := make(map[string]any, len(held))
		for key, item := range held {
			out[key] = placed(item, names)
		}

		return out
	}

	return value
}

func mergedClaims(base, overrides map[string]any) map[string]any {
	held := make(map[string]any, len(base))
	for key, value := range base {
		held[key] = value
	}

	for key, value := range overrides {
		if value == nil {
			delete(held, key)
		} else {
			held[key] = value
		}
	}

	return held
}

func timedClaims(claims map[string]any, times []string) map[string]any {
	now := time.Now().Unix()

	for _, name := range times {
		if offset, ok := claims[name].(float64); ok {
			claims[name] = now + int64(offset)
		}
	}

	return claims
}

func rawSegment(value any) string {
	encoded, _ := json.Marshal(value)

	return base64.RawURLEncoding.EncodeToString(encoded)
}

func signedCase(t *testing.T, contract tokenContract, held tokenCase, names map[string]string) string {
	t.Helper()

	if held.Raw != nil {
		return *held.Raw
	}

	shape := contract.Tokens[held.Token]
	header := mergedClaims(shape.Header, held.Header)
	claims := timedClaims(placed(mergedClaims(shape.Claims, held.Claims), names).(map[string]any), contract.Times)
	key := held.Key
	if key == "" {
		key = "signing"
	}

	if key == "none" {
		return rawSegment(header) + "." + rawSegment(claims) + "."
	}

	algorithm := jose.SignatureAlgorithm(header["alg"].(string))
	options := &jose.SignerOptions{}
	if typ, ok := header["typ"].(string); ok {
		options = options.WithType(jose.ContentType(typ))
	}

	var signing jose.SigningKey

	if key == "secret" {
		signing = jose.SigningKey{Algorithm: algorithm, Key: []byte(contract.Secret)}
	} else {
		var jwk jose.JSONWebKey
		if err := json.Unmarshal(contract.Keys[key], &jwk); err != nil {
			t.Fatal(err)
		}

		if kid, ok := header["kid"].(string); ok {
			jwk.KeyID = kid
		}

		signing = jose.SigningKey{Algorithm: algorithm, Key: jwk}
	}

	signer, err := jose.NewSigner(signing, options)
	if err != nil {
		t.Fatal(err)
	}

	token, err := jwt.Signed(signer).Claims(claims).Serialize()
	if err != nil {
		t.Fatal(err)
	}

	return token
}

func contractIssuer(t *testing.T, contract tokenContract) *Issuer {
	t.Helper()

	var server *httptest.Server

	mux := http.NewServeMux()
	mux.HandleFunc("GET /.well-known/openid-configuration", func(response http.ResponseWriter, _ *http.Request) {
		writeJSON(response, http.StatusOK, placed(contract.Discovery, map[string]string{"issuer": server.URL}))
	})
	mux.HandleFunc("GET /.well-known/jwks.json", func(response http.ResponseWriter, _ *http.Request) {
		response.Header().Set("Content-Type", "application/json")
		_, _ = response.Write(contract.JWKS)
	})

	server = httptest.NewServer(mux)
	t.Cleanup(server.Close)

	issuer, err := Discover(context.Background(), server.URL, quick)
	if err != nil {
		t.Fatal(err)
	}

	return issuer
}

func verifyCase(contract tokenContract, held tokenCase, issuer *Issuer, token string) error {
	client := &Client{Issuer: issuer, ID: contract.ClientID}
	expecting := contract.Expecting

	if held.Expecting != nil {
		if held.Expecting.Nonce != nil {
			expecting.Nonce = held.Expecting.Nonce
		}
		if held.Expecting.AccessToken != nil {
			expecting.AccessToken = held.Expecting.AccessToken
		}
		if held.Expecting.MaxAge != nil {
			expecting.MaxAge = held.Expecting.MaxAge
		}
	}

	switch held.Token {
	case "access":
		_, err := NewVerifier(issuer, contract.Resource).Verify(context.Background(), token)
		return err
	case "id":
		expected := Expectations{Nonce: *expecting.Nonce, AccessToken: *expecting.AccessToken}
		if *expecting.MaxAge > 0 {
			expected.MaxAge = time.Duration(*expecting.MaxAge) * time.Second
		}

		_, err := client.VerifyIDToken(context.Background(), token, expected)
		return err
	case "logout":
		_, err := client.VerifyLogoutToken(context.Background(), token)
		return err
	}

	return errors.New("no such token kind: " + held.Token)
}

func TestEveryTokenInTheContractEndsAsTheContractSays(t *testing.T) {
	contract := readTokens(t)
	issuer := contractIssuer(t, contract)
	names := map[string]string{"issuer": issuer.URL, "client_id": contract.ClientID, "resource": contract.Resource}

	for _, held := range contract.Cases {
		t.Run(held.Name, func(t *testing.T) {
			token := signedCase(t, contract, held, names)
			err := verifyCase(contract, held, issuer, token)

			if string(held.Outcome) == `"ok"` {
				if err != nil {
					t.Fatalf("refused: %v", err)
				}

				return
			}

			var outcome tokenOutcome
			if err := json.Unmarshal(held.Outcome, &outcome); err != nil {
				t.Fatal(err)
			}

			values := make([]any, len(outcome.Values))
			for index, value := range outcome.Values {
				values[index] = placed(value, names)
			}

			code, description := Failure(outcome.Failure, values...)

			var refused *InvalidToken
			if !errors.As(err, &refused) {
				t.Fatalf("got %v, wanted InvalidToken %s: %s", err, code, description)
			}

			if refused.Code != code || refused.Description != description {
				t.Errorf("got %s: %s, wanted %s: %s", refused.Code, refused.Description, code, description)
			}
		})
	}
}
