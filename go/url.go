package masks

import (
	"net/url"
	"strings"
)

func origin(held *url.URL) string {
	scheme := strings.ToLower(held.Scheme)
	host := strings.ToLower(held.Host)

	if (scheme == "https" && held.Port() == "443") || (scheme == "http" && held.Port() == "80") {
		host = strings.ToLower(held.Hostname())
	}

	return scheme + "://" + host
}

func htu(held *url.URL) string {
	plain := *held
	plain.RawQuery = ""
	plain.ForceQuery = false
	plain.Fragment = ""
	plain.RawFragment = ""

	return plain.String()
}

func tidied(held *url.URL) string {
	path := held.EscapedPath()
	if path == "/" {
		path = ""
	}

	return origin(held) + path
}

func tidiedString(raw string) (string, error) {
	held, err := url.Parse(raw)
	if err != nil {
		return "", err
	}

	return tidied(held), nil
}
