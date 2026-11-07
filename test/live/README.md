# The live run

`ruby test/live/run.rb [image]` boots a real masks from an image with compose, sets up its first
manager, and runs each SDK through six scenarios against it: the handshake, a sign-in, a refresh,
a step-up, a back-channel logout, and a DPoP-bound machine sign-in. It prints one row per SDK and
one column per scenario, and it fails when any cell does.

## How it runs

`run.rb` plays the browser. It signs the manager in over the JSON login API, approves the handshake,
answers each sign-in prompt, and signs out. Each SDK has a small live app in this directory that the
driver starts as a child process and talks to over stdin and stdout, one JSON object per line.

masks runs in a container. The live apps run on the host and listen on loopback, so masks reaches
them through `relay`, a socat sidecar in the masks container's network namespace that forwards each
app's port to `host.docker.internal`. `MASKS_OUTBOUND_ALLOWED` lets masks call loopback for that.
Every app URL uses `127.0.0.1`, since `localhost` also resolves to `::1`, which the allowlist does
not cover.

Options:

- `--only ruby,node` runs some of the SDKs.
- `--keep` leaves the stack running afterwards and remembers its owner in `.state.json`.
- `--attached` uses the stack a `--keep` run left behind, so a second run can skip the boot.

## The protocol

The driver starts an app as `<command> --port PORT`. The app serves HTTP on `127.0.0.1:PORT`,
prints `{"ready": true}` once it listens, and then answers one line for each line the driver
writes. An app that cannot do a step answers `{"error": "what went wrong"}`.

| Step | The driver sends | The app answers |
| --- | --- | --- |
| `handshake` | `issuer`, `name`, `resource`, `redirect_uri`, `return_to`, `backchannel_logout_uri`, `scope` (a list, ending in the namespace prefix the app claims, such as `live-ruby:`), and `signin_scope` (the list the sign-in client asks for) | `url`, the handshake URL, and `state` |
| `handshake:complete` | `url`, where masks sent the browser back to | `client_id` |
| `signin` | `prompt` and `max_age`, each null or set | `url`, the authorize URL |
| `signin:complete` | `url`, where masks sent the browser back to | `sub`, `sid`, `auth_time`, `amr`, and whether `refresh_token` and `id_token` came back |
| `refresh` | nothing more | `rotated`, true when both tokens changed, and `sub` |
| `logout` | `timeout` in seconds | `sid` and `sub` from the logout token masks posted to `/backchannel` |
| `machine` | `scope` and `resource` | `client_id`, `bound`, `active`, `scope`, and `jkt`, true when introspection shows the machine's key |
| `quit` | nothing more | nothing; the app exits |

The app:

- completes the handshake with the SDK and keeps the registration, then builds the sign-in client
  from it with `signin_scope`
- verifies the ID token with the nonce from the start, and with `max_age` when the driver sent one
- answers `POST /backchannel` by verifying the `logout_token` form field with the SDK and holding
  the result for the `logout` step
- for `machine`, enrolls a machine through the app, registers it with the initial access token as
  `private_key_jwt` with its own key and `dpop_bound_access_tokens`, asks for client credentials
  bound to a second key, and introspects the token through the app

`ruby.rb` is the reference.
