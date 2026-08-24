# Making a failure happen: faults, credentials, the clock

Read this when the task is about a failure, or a case needs a condition the
vendor will not produce on demand. A bad request — wrong content type,
unknown field, bad id — gets the vendor's real error with no setup. Anything
else is a `faults` row on the sandbox, armed with `veris.sh fault`:

```
veris.sh fault <sandbox> [service] <METHOD> <path> <outcome> [status] [phase] [remaining]
veris.sh fault sb1 quickbooks POST /v3/company/123/invoice hang  0   after 1     # write commits, response lost
veris.sh fault sb1 stripe     POST /v1/charges              error 429 before 2   # two throttles, then normal
veris.sh fault sb1 stripe     POST /v1/charges              latency 8000        # 8 s delay
```

| the report says | the row |
|---|---|
| the response never came back, but the write happened | `hang` (or `error` with a 5xx) with phase `after` — the committed-but-unanswered write |
| we got throttled | `error 429`, `remaining 2`: two matching requests are throttled, then responses resume; not an upstream quota window |
| the vendor refused | `error <status>` with a status **the manual lists** — an unlisted one is refused with `422` naming the allowed set |
| it was slow enough to time out | `latency <ms>` |
| the request was lost before the write | `hang` with phase `before` |

- `path` is the application's concrete path without scheme, host, query or
  fragment; copy it from `veris.sh requests` when an SDK hides it.
- `remaining 1` spends the fault once. Delete persistent faults in cleanup:
  `DELETE {control_url}/veris/data` with the row's id.
- The full row supports more than the script exposes — `match` on body or
  query fields (`{"body.resource_id":"…"}`, `{"query.expand":"items"}`; the
  manual lists the keys a service supports), `error.code`, `error.headers`,
  `{"status":502,"raw":true}` for a non-JSON gateway response, and
  `idempotency: "bind"|"unbound"` for whether an error replays on key reuse.
  Post it yourself:
  ```http
  POST {control_url}/veris/data
  {"data":{"faults":[{"method":"POST","path":"/vendor/path",
    "match":{"body.resource_id":"test-owned-id"},
    "outcome":"error","error":{"status":429,"code":"<listed>","headers":{"Retry-After":"2"}},
    "remaining":2}]}}
  ```

## Then drive the real code through it

A fault proves nothing until the application's own code path meets it: the
endpoint, worker, job or handler the task names — not a curl standing in for
it. Arm the row, run that path under `veris-proxy` ([proxy.md](proxy.md)),
then read the ledger: `veris.sh data <sandbox> <table>` shows whether the
write landed, and `veris.sh requests` shows what the client did next. That
before-and-after is the evidence the PR quotes.

## Credentials

In the default mode any well-formed API key, token, or OAuth client pair
works — published, seeded, or the application's own — so a wrong-key test
passes for the wrong reason. To test rejection, arm value checking first:

```http
PATCH {control_url}/veris/data
{"data":{"auth":[{"id":1,"mode":"enforced"}]}}
```

and set it back to `"permissive"` when done. OAuth access and refresh tokens
are the exception in both modes: only tokens the sandbox issued work. Run the
application's own connect flow against the sandbox URLs, or take the seeded
one from `veris.sh token`; never insert tokens by hand.

## The clock

One `clock` row is shared by every service in the sandbox:

```http
PATCH {control_url}/veris/data
{"data":{"clock":[{"id":1,"offset_seconds":2678400}]}}
```

It advances vendor time — expiry, retention, replay windows. Advance the
application's own test clock separately; keep signed-token tests near wall
time; never move it backwards during a suite. Moving it can expire the
credential you are holding: re-authenticate and measure again rather than
reading the 401 as the vendor's answer.
