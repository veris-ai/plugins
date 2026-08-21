# Sandbox state, faults, and the clock

Every `/veris/*` call goes to a service's `control_url` (from `get_sandbox`;
it equals `url` for HTTP services). Call these from test setup, teardown, and
inspection code only — the application under test keeps using the vendor
interface, and `veris-proxy` routes it.

## Inspect and change state

- `GET /veris/manual` — the service's credentials, values, and controls. Read
  it first; it names what makes a repeated write safe, or that nothing does.
- `GET /veris/schema` — entity names, fields, required values, enums, and
  each table's description, which states the rule that governs it.
- `GET /veris/operations` — the method/path list, where a service publishes
  one; most answer `404`.
- `GET /veris/data` — row counts. `GET /veris/data?entity_type=<name>` — the
  first 100 rows; page with `limit` (1–1000) and `offset`; the response
  reports `total`.
- `POST /veris/data` — add exact rows. `PATCH` changes rows by primary key;
  `DELETE` removes them.
- `POST /veris/snapshot` — a stable debugging view, not a checkpoint.
- A column holding a file's bytes answers
  `"content": "[content hidden — download it from the vendor API]"`; `null`
  and `""` mean no bytes; size and checksum columns return in full.

Seed in this envelope, with names from `/veris/schema`:

```http
POST {control_url}/veris/data
Content-Type: application/json

{"data":{"<entity>":[{"<primary-key>":"test-owned-id","<field>":"value"}]}}
```

Keep test state small and keep the ids you create; discover existing ids
from sandbox state, never by guessing or copying from another sandbox. Use a
vendor test value, fixture, or named profile only when the manual names it.

## Credentials

Any well-formed API key, personal access token, or OAuth client id and
secret works — published, seeded, or the application's own — so a wrong-key
test passes for the wrong reason until value checking is armed:

```http
PATCH {control_url}/veris/data

{"data":{"auth":[{"id":1,"mode":"enforced"}]}}
```

Armed, only published credentials work; set `mode` back to `"permissive"`
when done (`reset_sandbox` also resets it). OAuth access and refresh tokens
are the exception: only tokens the sandbox issued work — run the
application's own connect and callback flow against the sandbox URLs and let
the callback store them; never insert them by hand. A missing or malformed
credential is always rejected.

## Faults

A bad request — wrong content type, unknown field, bad id — gets the
vendor's real error with no setup. For a failure you cannot cause yourself,
add a `faults` row through `POST /veris/data`:

```json
{"data":{"faults":[{
  "method": "POST",
  "path": "/vendor/path",
  "match": {"body.resource_id": "test-owned-id"},
  "outcome": "hang",
  "phase": "after",
  "remaining": 1
}]}}
```

- `path` is the application's concrete path without scheme, host, query, or
  fragment; copy it from `/veris/requests` when an SDK hides it. Query
  conditions go in `match`, e.g. `{"query.expand":"items"}`; the manual lists
  the `match` keys a service supports.
- `outcome: "error"` with `error.status` and optional `error.code` returns a
  vendor-shaped error. **The status must be one the manual lists** — an
  unlisted one is refused with `422` naming the allowed set.
  `error.headers` carries documented headers into the response;
  `{"status":502,"raw":true}` returns a non-JSON gateway response for the
  supported statuses.
- `outcome: "hang"` sends no response. `latency_ms` delays it.
- `phase: "after"` applies the vendor action, then loses the response — the
  committed-but-unanswered write.
- `remaining: 1` spends the fault once. Delete persistent faults in cleanup.
- `idempotency: "bind"` or `"unbound"` decides whether the error replays on
  idempotency-key reuse; the manual states the default.

A finite throttle, with the manual's status, code, and headers:

```json
{"data":{"faults":[{"method":"GET","path":"/vendor/path","outcome":"error",
"error":{"status":429,"code":"<listed-code>","headers":{"Retry-After":"2"}},
"remaining":2}]}}
```

Two matching requests get the throttle, then normal responses resume; this
does not model an upstream quota window.

## The clock

One `clock` row is shared by every service in a sandbox:

```json
{"data":{"clock":[{"id":1,"offset_seconds":2678400}]}}
```

Send it with `PATCH /veris/data` to advance vendor time; advance the
application's own test clock separately. Keep JWT and signed-callback tests
near wall time — client libraries may check timestamps against the machine
clock. Never move the sandbox clock backwards during a suite; derive
operational dates from the current clock, not fixed dates.

## Read-back

`GET {control_url}/veris/requests` — method, path, status, headers, bodies,
newest first (the query string is not recorded yet); `?order=asc` reverses,
`?limit=` returns more; credentials,
cookies, OAuth codes, and private keys appear as `[REDACTED]`.
`GET /veris/data?entity_type=<name>` — what the vendor stored.
