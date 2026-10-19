# Reporting a security hole

masks is an auth server, so a hole in it is a hole in every app behind it. Reports are welcome and
answered.

## How to report

Use [private vulnerability reporting](https://github.com/masksrb/masks/security/advisories/new)
on GitHub. It opens a draft advisory that only you and the maintainers can read.

Do not open a public issue for a hole. Do not post it in a discussion or a pull request.

Say what you found, how to reproduce it, and which version or commit you tested. A proof of concept
helps. You do not need to propose a fix.

## What happens next

| Within  | masks                                                              |
| ------- | ------------------------------------------------------------------ |
| 3 days  | Answers the report and says whether it is a hole.                  |
| 14 days | Has a fix on `main` for a hole that lets someone in or leaks data. |
| 90 days | Has a fix on `main` for every other confirmed hole.                |

A fix ships in the next release, and the advisory is published with credit to the reporter unless
they ask otherwise. A hole that affects a self-hosted deployment is also written up in the release
notes with what an operator should do.

## What counts

A hole is anything that lets someone sign in as a person they are not, read or change a tenant's
data without its roles, get a token they were not granted, or take a tenant's signing or encryption
keys. Rate limit bypasses, open redirects, and a way to stop other people signing in count too.

A dependency advisory with no reachable path in masks, a missing header on the docs site, and a
report from an automated scanner with no reproduction are not holes. They are still welcome as
public issues.

## Versions

Only the latest release gets fixes. Upgrade before you report, if you can, because the hole may be
closed already. The [security guide](https://masks.pages.dev/guides/security/) says what masks does
to protect a deployment and what an operator still has to do.
