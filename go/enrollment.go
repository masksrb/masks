package masks

import (
	"context"
	"errors"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"time"
)

type EnrollmentRequest struct {
	Scope    []string
	Name     string
	Lifetime time.Duration
}

type Enrollment struct {
	InitialAccessToken string    `json:"initial_access_token"`
	Scope              string    `json:"scope"`
	ExpiresIn          int64     `json:"expires_in"`
	Expiry             time.Time `json:"expiry,omitzero"`
}

func (e *Enrollment) Scopes() []string {
	return strings.Fields(e.Scope)
}

func (c *Client) Enroll(ctx context.Context, asked EnrollmentRequest) (*Enrollment, error) {
	endpoint, err := c.Issuer.endpoint("enrollment_endpoint", c.Issuer.Metadata.EnrollmentEndpoint)
	if err != nil {
		return nil, err
	}

	form := url.Values{}
	form.Set("scope", strings.Join(asked.Scope, " "))

	if asked.Name != "" {
		form.Set("client_name", asked.Name)
	}

	if asked.Lifetime > 0 {
		form.Set("expires_in", strconv.FormatInt(max(int64(asked.Lifetime/time.Second), 1), 10))
	}

	held := &Enrollment{}

	if err := c.post(ctx, endpoint, form, false, held); err != nil {
		return nil, err
	}

	if held.InitialAccessToken == "" {
		return nil, &Error{Code: "server_error", Description: "the enrollment endpoint answered without an initial access token"}
	}

	if held.ExpiresIn > 0 {
		held.Expiry = time.Now().Add(time.Duration(held.ExpiresIn) * time.Second)
	}

	return held, nil
}

func (c *Client) Unenroll(ctx context.Context, machineID string) error {
	endpoint, err := c.Issuer.endpoint("enrollment_endpoint", c.Issuer.Metadata.EnrollmentEndpoint)
	if err != nil {
		return err
	}

	if machineID == "" || machineID == "." || machineID == ".." {
		return errors.New("masks: unenrolling needs the machine's client_id")
	}

	return c.call(ctx, http.MethodDelete, strings.TrimSuffix(endpoint, "/")+"/"+url.PathEscape(machineID), url.Values{}, false, nil)
}
