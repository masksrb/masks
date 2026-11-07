package masks

import (
	"context"
	"testing"

	"github.com/masksrb/masks/go/masktest"
)

func TestASignInCompletesAgainstTheFake(t *testing.T) {
	held := masktest.New(t)
	client := shookHands(t, held)

	started, err := client.AuthCodeURL(AuthRequest{Scope: []string{"openid", "offline_access"}})
	if err != nil {
		t.Fatal(err)
	}

	signed, err := client.Complete(context.Background(), visit(t, started.URL), started)
	if err != nil {
		t.Fatal(err)
	}

	if signed.Identity.Subject != held.Actor.Subject || signed.Token.RefreshToken == "" || signed.Token.IDToken == "" {
		t.Fatalf("unexpected sign-in %+v", signed)
	}
}

func TestARefreshAgainstTheFakeRotatesTheToken(t *testing.T) {
	held := masktest.New(t)
	client := shookHands(t, held)

	started, err := client.AuthCodeURL(AuthRequest{Scope: []string{"openid", "offline_access"}})
	if err != nil {
		t.Fatal(err)
	}

	signed, err := client.Complete(context.Background(), visit(t, started.URL), started)
	if err != nil {
		t.Fatal(err)
	}

	renewed, err := client.Refresh(context.Background(), signed.Token.RefreshToken, TokenRequest{})
	if err != nil {
		t.Fatal(err)
	}

	if renewed.AccessToken == signed.Token.AccessToken || renewed.RefreshToken == signed.Token.RefreshToken || renewed.RefreshToken == "" {
		t.Fatalf("the refresh did not rotate: %+v", renewed)
	}

	if _, err := client.Refresh(context.Background(), signed.Token.RefreshToken, TokenRequest{}); !HasCode(err, "invalid_grant") {
		t.Fatalf("expected the spent refresh token to be refused, got %v", err)
	}
}

func TestALogoutTokenFromTheFakeVerifies(t *testing.T) {
	held := masktest.New(t)
	client := shookHands(t, held)

	logout, err := client.VerifyLogoutToken(context.Background(), held.LogoutToken(map[string]any{"aud": client.ID, "sid": "sid-ada", "sub": "ada"}))
	if err != nil {
		t.Fatal(err)
	}

	if logout.SessionID != "sid-ada" || logout.Subject != "ada" {
		t.Fatalf("unexpected %+v", logout)
	}
}
