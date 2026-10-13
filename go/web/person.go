package web

import (
	"context"
	"encoding/json"
	"slices"
	"strings"

	masks "github.com/masksrb/masks/go"
)

var identityClaims = []string{
	"sub", "name", "preferred_username", "email", "email_verified", "tenant", "picture", "masks:avatars",
	"org", "orgs", "groups", "sid",
}

type Person struct {
	SignedIn      bool                 `json:"signed_in"`
	Subject       string               `json:"subject,omitempty"`
	Name          string               `json:"name,omitempty"`
	Nickname      string               `json:"nickname,omitempty"`
	Email         string               `json:"email,omitempty"`
	EmailVerified bool                 `json:"email_verified,omitempty"`
	Picture       string               `json:"picture,omitempty"`
	Avatars       map[string]string    `json:"avatars,omitempty"`
	Tenant        *masks.Tenant        `json:"tenant,omitempty"`
	Organization  *masks.Organization  `json:"organization,omitempty"`
	Organizations []masks.Organization `json:"organizations,omitempty"`
	Groups        []string             `json:"groups,omitempty"`
	Scopes        []string             `json:"scopes"`
	Privileges    []string             `json:"privileges"`
	ExpiresAt     int64                `json:"expires_at,omitempty"`
	AccountURL    string               `json:"account_url,omitempty"`
	ClientID      string               `json:"-"`
	SessionID     string               `json:"-"`
	AccessToken   string               `json:"-"`
	Identity      *masks.Identity      `json:"-"`
	Claims        *masks.Claims        `json:"-"`
}

func (p *Person) HasScope(scope string) bool {
	return p.SignedIn && slices.Contains(p.Scopes, scope)
}

func (p *Person) HasRole(roles ...string) bool {
	return p.SignedIn && p.Organization.HasRole(roles...)
}

func (p *Person) HasPrivilege(names ...string) bool {
	if !p.SignedIn || len(names) == 0 {
		return false
	}

	for _, name := range names {
		if !slices.Contains(p.Privileges, name) {
			return false
		}
	}

	return true
}

func (p *Person) Claim(name string, into any) bool {
	return p.Identity != nil && p.Identity.Claim(name, into)
}

func (p *Person) member(privilege Privilege) *refusal {
	if len(privilege.Role) == 0 && privilege.Organization == "" {
		return nil
	}

	held := p.Organization
	if held == nil || held.Key == "" {
		return &refusal{code: "insufficient_organization", description: "this sign-in names no organization", scope: masks.ScopeOrganization}
	}

	if privilege.Organization != "" && held.Key != privilege.Organization && held.ID != privilege.Organization {
		return &refusal{code: "insufficient_organization", description: "this sign-in is for " + held.Key + ", not " + privilege.Organization}
	}

	if len(privilege.Role) == 0 || held.HasRole(privilege.Role...) {
		return nil
	}

	return &refusal{code: "insufficient_role", description: held.Role + " in " + held.Key + " is not " + strings.Join(privilege.Role, " or ")}
}

func (p *Person) holds(privilege Privilege) bool {
	for _, scope := range privilege.Scope {
		if !slices.Contains(p.Scopes, scope) {
			return false
		}
	}

	return p.member(privilege) == nil
}

func (a *App) personFrom(identity *masks.Identity, token *masks.Token, account string) *Person {
	held := &Person{
		SignedIn:    true,
		Scopes:      token.Scopes(),
		AccessToken: token.AccessToken,
		AccountURL:  account,
		Identity:    identity,
	}

	if !token.Expiry.IsZero() {
		held.ExpiresAt = token.Expiry.Unix()
	}

	if identity != nil {
		held.Subject = identity.Subject
		held.Name = identity.Name
		held.Nickname = identity.PreferredUsername
		held.Email = identity.Email
		held.EmailVerified = identity.EmailVerified
		held.Picture = identity.Photo()
		held.Tenant = identity.Tenant
		held.Organization = identity.Organization
		held.Organizations = identity.Organizations
		held.Groups = identity.Groups
		held.SessionID = identity.SessionID

		held.Avatars = map[string]string{}

		for style, url := range identity.Avatars {
			if url != "" {
				held.Avatars[style] = url
			}
		}

		if len(held.Avatars) == 0 {
			held.Avatars = nil
		}
	}

	a.privilege(held)

	return held
}

func (a *App) personFromClaims(claims *masks.Claims, token string) *Person {
	held := &Person{
		SignedIn:     true,
		Subject:      claims.Subject,
		Scopes:       claims.Scopes(),
		Tenant:       claims.Tenant,
		Organization: claims.Organization,
		ClientID:     claims.ClientID,
		AccessToken:  token,
		Claims:       claims,
	}

	if claims.Expiry != nil {
		held.ExpiresAt = claims.Expiry.Time().Unix()
	}

	a.privilege(held)

	return held
}

func (a *App) privilege(held *Person) {
	held.Privileges = []string{}

	for _, name := range a.names {
		if held.holds(a.config.Privileges[name]) {
			held.Privileges = append(held.Privileges, name)
		}
	}
}

type personKey struct{}

func PersonFrom(ctx context.Context) *Person {
	if held, ok := ctx.Value(personKey{}).(*Person); ok && held != nil {
		return held
	}

	return &Person{Scopes: []string{}, Privileges: []string{}}
}

func WithPerson(ctx context.Context, held *Person) context.Context {
	return context.WithValue(ctx, personKey{}, held)
}

func (p *Person) MarshalJSON() ([]byte, error) {
	type plain Person

	if !p.SignedIn {
		return json.Marshal(map[string]bool{"signed_in": false})
	}

	return json.Marshal((*plain)(p))
}
