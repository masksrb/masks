package masks

import (
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
)

func Failure(key string, values ...any) (code, description string) {
	held, ok := failures[key]
	if !ok {
		panic("masks: no failure named " + key)
	}

	return held[0], fmt.Sprintf(held[1], values...)
}

func Saying(key string, values ...any) string {
	_, description := Failure(key, values...)

	return description
}

func worded(code, description string) string {
	if description == "" {
		return "masks: " + code
	}

	return "masks: " + code + ": " + description
}

type coded interface {
	error
	failureCode() string
}

func HasCode(err error, code string) bool {
	var held coded

	return errors.As(err, &held) && held.failureCode() == code
}

type Refused struct {
	Code        string `json:"error"`
	Description string `json:"error_description,omitempty"`
	URI         string `json:"error_uri,omitempty"`
	Status      int    `json:"-"`
}

func (e *Refused) Error() string       { return worded(e.Code, e.Description) }
func (e *Refused) failureCode() string { return e.Code }

func refuse(key string, values ...any) *Refused {
	code, description := Failure(key, values...)

	return &Refused{Code: code, Description: description}
}

type InvalidToken struct {
	Code        string
	Description string
	Missing     bool

	cause error
}

func (e *InvalidToken) Error() string       { return worded(e.Code, e.Description) }
func (e *InvalidToken) failureCode() string { return e.Code }
func (e *InvalidToken) Unwrap() error       { return e.cause }

func (e *InvalidToken) Challenged() (code, description string) {
	if e.Missing {
		return "", ""
	}

	return e.Code, e.Description
}

func invalid(key string, values ...any) *InvalidToken {
	code, description := Failure(key, values...)

	return &InvalidToken{Code: code, Description: description, Missing: key == "no_token"}
}

type Forbidden struct {
	Code        string
	Description string
	Scope       string
}

func (e *Forbidden) Error() string       { return worded(e.Code, e.Description) }
func (e *Forbidden) failureCode() string { return e.Code }

type Unavailable struct {
	Description string

	cause error
}

func (e *Unavailable) Error() string       { return worded("temporarily_unavailable", e.Description) }
func (e *Unavailable) failureCode() string { return "temporarily_unavailable" }
func (e *Unavailable) Unwrap() error       { return e.cause }

func unavailable(key string, values ...any) *Unavailable {
	return &Unavailable{Description: Saying(key, values...)}
}

type Insecure struct {
	Description string
}

func (e *Insecure) Error() string       { return worded("insecure_url", e.Description) }
func (e *Insecure) failureCode() string { return "insecure_url" }

func insecure(key string, values ...any) *Insecure {
	return &Insecure{Description: Saying(key, values...)}
}

type Foreign struct {
	Description string
}

func (e *Foreign) Error() string       { return worded("foreign_origin", e.Description) }
func (e *Foreign) failureCode() string { return "foreign_origin" }

func foreign(key string, values ...any) *Foreign {
	return &Foreign{Description: Saying(key, values...)}
}

type DelegationRefused struct {
	Code        string
	Description string
	Status      int
	Secret      string

	cause error
}

func (e *DelegationRefused) Error() string       { return worded(e.Code, e.Description) }
func (e *DelegationRefused) failureCode() string { return e.Code }
func (e *DelegationRefused) Unwrap() error       { return e.cause }

func (e *DelegationRefused) SignInAgain() bool {
	return e.Code == "login_required" || e.Code == "interaction_required"
}

func delegationRefused(key string, values ...any) *DelegationRefused {
	code, description := Failure(key, values...)

	return &DelegationRefused{Code: code, Description: description}
}

type DelegationUnavailable struct {
	Description string
	Secret      string

	cause error
}

func (e *DelegationUnavailable) Error() string {
	return worded("temporarily_unavailable", e.Description)
}

func (e *DelegationUnavailable) failureCode() string { return "temporarily_unavailable" }
func (e *DelegationUnavailable) Unwrap() error       { return e.cause }

const readLimit = 1 << 20

func refused(response *http.Response) error {
	body, _ := io.ReadAll(io.LimitReader(response.Body, readLimit))
	held := &Refused{Status: response.StatusCode}

	if json.Unmarshal(body, held) != nil || held.Code == "" {
		held.Code, held.Description = Failure("answered_status", response.Request.URL.Redacted(), response.StatusCode)
	}

	return held
}
