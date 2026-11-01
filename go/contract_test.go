package masks

import (
	"encoding/json"
	"errors"
	"os"
	"regexp"
	"strings"
	"testing"
)

func is[T error](err error) bool {
	var held T

	return errors.As(err, &held)
}

type contract struct {
	Kinds []struct {
		Name  string            `json:"name"`
		Names map[string]string `json:"names"`
	} `json:"kinds"`
	Failures map[string]struct {
		Kind        string `json:"kind"`
		Code        string `json:"code"`
		Description string `json:"description"`
	} `json:"failures"`
}

func readContract(t *testing.T) contract {
	t.Helper()

	body, err := os.ReadFile("../test/contract/errors.json")
	if err != nil {
		t.Fatal(err)
	}

	var held contract
	if err := json.Unmarshal(body, &held); err != nil {
		t.Fatal(err)
	}

	return held
}

var placeholder = regexp.MustCompile(`\{[a-z_]+\}`)

func TestEveryKindInTheContractIsAGoTypeOfItsOwnName(t *testing.T) {
	for _, kind := range readContract(t).Kinds {
		if kind.Names["go"] != "*masks."+kind.Name {
			t.Errorf("%s is named %q for Go", kind.Name, kind.Names["go"])
		}
	}
}

func TestEveryFailureInTheContractIsRaisedWithItsCodeAndDescription(t *testing.T) {
	for key, held := range readContract(t).Failures {
		names := placeholder.FindAllString(held.Description, -1)
		values := make([]any, 0, len(names))
		description := held.Description

		for _, name := range names {
			value := strings.ToUpper(strings.Trim(name, "{}"))
			values = append(values, value)
			description = strings.Replace(description, name, value, 1)
		}

		if code, said := Failure(key, values...); code != held.Code || said != description {
			t.Errorf("%s: Failure gave %q %q", key, code, said)
		}

		var err error

		switch held.Kind {
		case "Refused":
			err = refuse(key, values...)
		case "InvalidToken":
			err = invalid(key, values...)
		case "Forbidden":
			code, said := Failure(key, values...)
			err = &Forbidden{Code: code, Description: said}
		case "Unavailable":
			err = unavailable(key, values...)
		case "Insecure":
			err = insecure(key, values...)
		case "Foreign":
			err = foreign(key, values...)
		case "DelegationRefused":
			code, said := Failure(key, values...)
			err = &DelegationRefused{Code: code, Description: said}
		case "DelegationUnavailable":
			err = &DelegationUnavailable{Description: Saying(key, values...)}
		default:
			t.Fatalf("%s names a kind Go does not have: %s", key, held.Kind)
		}

		if want := "masks: " + held.Code + ": " + description; err.Error() != want {
			t.Errorf("%s: %q, wanted %q", key, err.Error(), want)
		}

		if !HasCode(err, held.Code) {
			t.Errorf("%s: HasCode does not see %s", key, held.Code)
		}
	}
}

func TestAMissingTokenIsTheOneFailureThatSaysSo(t *testing.T) {
	if !invalid("no_token").Missing || invalid("expired").Missing {
		t.Fatal("Missing is set for the wrong failure")
	}

	if code, description := invalid("no_token").Challenged(); code != "" || description != "" {
		t.Fatalf("a missing token challenged with %q %q", code, description)
	}
}
