# Making a failure happen: faults, credentials, the clock

Read this when the task is about a failure, or a case needs a condition the vendor
will not produce on demand. A bad request, wrong content type, unknown field, bad
id, gets the vendor's real error with no setup. Anything else is a **fault row** in
the twin's `faults` table, added like any other row:

```
veris sandbox data add faults.json
```

```json
{"stripe": {"faults": [
  {"method": "POST", "path": "/v3/company/123/invoice", "outcome": "hang", "phase": "after", "remaining": 1},
  {"method": "POST", "path": "/v1/charges", "outcome": "error",
   "error": {"status": 429, "code": "<a code the manual lists>", "headers": {"Retry-After": "2"}},
   "remaining": 2},
  {"method": "POST", "path": "/v1/charges", "latency_ms": 8000}
]}}
```

`outcome: "error"` needs an `error` object; a row with one and not the other is
refused. A slow-but-normal response is `latency_ms` with **no** `outcome`, the third
row above.

| the report says | the row |
|---|---|
| the response never came back, but the write happened | `hang` (or `error` with a 5xx) with `phase: "after"`: the committed-but-unanswered write |
| we got throttled | `error` 429, `remaining: 2`: two matching requests are throttled, then responses resume; not an upstream quota window |
| the vendor refused | `error <status>` with a status **the manual lists**; an unlisted one is refused with 422 naming the allowed set |
| it was slow enough to time out | `latency_ms` |
| the request was lost before the write | `hang` with `phase: "before"` |

- `path` is the vendor request path without scheme, host, query or fragment; copy it
  from `veris sandbox trace` when an SDK hides it. A dynamic segment can be a
  `{name}` template: `/v1/payment_intents/{id}/confirm` matches every id and binds
  `path.id` for `match` to narrow on. One templated row beats a row per id, and it is
  the only way to arm a fault before the id exists.
- **An SDK may spend the fault before your code sees it.** Most vendor clients retry
  5xx and connection errors internally, reusing the caller's idempotency key. A Stripe
  Node client was measured absorbing an armed 500 inside a single call, so it never
  reached the code under test, which reads as the bug not reproducing. If an armed
  failure vanishes, check the client's retry setting before doubting the fault. Then
  arm a class the SDK does not retry, a 4xx such as 429, to isolate the behaviour you
  mean to exercise.
- `remaining: 1` spends the fault once. Persistent faults stay until deleted;
  `veris sandbox data get <twin> faults` shows what is armed, and cleanup disarms one
  by its id:
  ```
  veris sandbox data delete <twin> faults id=<fault id> --yes
  ```
- A row can also carry `match` on body, query or path fields:
  `{"body.resource_id": "…"}`, `{"query.expand": "items"}`, `{"path.id": "pi_123"}`.
  The manual lists the keys a twin supports. A row can carry `error.code` and
  `error.headers` as well, `{"status": 502, "raw": true}` for a non-JSON gateway
  response, and `idempotency: "bind"|"unbound"` for whether an error replays on key
  reuse. `bind` is accepted only on a `phase: before`, `outcome: error` row without
  `raw`, since nothing else produces a response the key can store.

## A GraphQL twin

Every request is one `POST /graphql`, so a row with that path and no `match` fires on
all of them, usually not what a test wants. Narrow to the operation and its
variables: `"match": {"graphql.operation": "issueCreate"}`, and
`graphql.variables.<path>` narrows further. The manual lists which of these a twin
supports.

## Then drive the real code through it

A fault proves nothing until the application's own code path meets it: the endpoint,
worker, job or handler the task names, not a curl standing in for it. Arm the row,
run that path with `veris run` ([run.md](run.md)), then read the ledger:
`veris sandbox data get <twin> <table>` shows whether the write landed, and
`veris sandbox trace --tier fault` shows the injected exchange, `--tier handler` what
the client did next. That before-and-after is the evidence the PR quotes.

## Credentials

For a twin that checks API keys or OAuth client credentials itself, permissive
mode accepts well-formed values without requiring a match in its state. OAuth tokens
and companion-issuer verification still follow the provenance rules below.
To test an unknown API key or client credential being rejected, arm value checking first:

```
veris sandbox data set <twin> auth id=1 mode=enforced
```

and set it back with `mode=permissive` when done. `auth` is a singleton row, so `set` is
the only way to change it. OAuth access and refresh tokens are the exception in both
modes: only tokens the sandbox issued work. Run the app's own connect flow against the
sandbox, or take the seeded one from `veris sandbox data get <twin> oauth_tokens`; never
insert tokens by hand.

Some twins do not judge credentials themselves; they verify what a companion identity
twin in the same environment minted. There the values are always checked, and this row
does not change acceptance. Arming it and seeing no difference is the design, not a
broken sandbox. The `auth` table's description in
`veris sandbox data schema <twin> --table auth` says which kind a twin is; read it
before concluding anything from an unchanged result.

## The clock

One clock is shared by every twin in the sandbox, and it is set on the sandbox, never
through one twin's data:

```
veris sandbox clock                                  # read it: "live (+7d)" or "frozen at <instant>"
veris sandbox clock set --offset 31d                 # advance vendor time
veris sandbox clock set --freeze-at 2026-03-01T09:00:00Z
veris sandbox clock set --live                       # back to wall-aligned time
```

`--offset` takes Go durations plus `d` and `w` (`90m`, `36h`, `+7d`, `-2w`,
`1d12h`); `--freeze-at` takes RFC 3339 or a bare Unix second. Advancing it moves
vendor time: expiry, retention, replay windows. Freezing it stops vendor time at that
instant, which is what makes a retention or expiry boundary reproducible instead of
racing wall time. The command prints the complete resulting clock. Moving time
backwards is allowed, and it prints the server's warning as a `!` line, because data
is then dated in the future. Never move it backwards during a suite. Advance the
application's own test clock separately. `veris sandbox reset` sets the clock live
again along with the data.

The sandbox's clock is the only one that moves. A test that signs tokens or verifies
signatures has to keep the application's clock in step with it, or keep the moment it
mints the token in step with it. Otherwise the skew becomes the result. Moving the
clock can also expire the credential you are holding: re-authenticate and measure
again, rather than reading that 401 as the vendor's answer. A frozen clock pauses
outbound webhook delivery until it is set live again.
