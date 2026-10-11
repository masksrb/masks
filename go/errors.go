package masks

import (
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
)

type Error struct {
	Code        string `json:"error"`
	Description string `json:"error_description,omitempty"`
	URI         string `json:"error_uri,omitempty"`
	Status      int    `json:"-"`
}

func (e *Error) Error() string {
	if e.Description == "" {
		return "masks: " + e.Code
	}

	return fmt.Sprintf("masks: %s: %s", e.Code, e.Description)
}

func HasCode(err error, code string) bool {
	var held *Error

	return errors.As(err, &held) && held.Code == code
}

var (
	ErrInvalidToken = errors.New("masks: invalid token")
	ErrInsecure     = errors.New("masks: plain http is allowed only on this machine")
	ErrForeign      = errors.New("masks: that URL belongs to another origin")
)

const readLimit = 1 << 20

func refused(response *http.Response) error {
	body, _ := io.ReadAll(io.LimitReader(response.Body, readLimit))
	held := &Error{Status: response.StatusCode}

	if json.Unmarshal(body, held) != nil || held.Code == "" {
		held.Code = "server_error"
		held.Description = fmt.Sprintf("%s answered %d", response.Request.URL.Redacted(), response.StatusCode)
	}

	return held
}
