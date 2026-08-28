# Making a failure happen: faults, credentials, the clock

Read this when the task is about a failure, or a case needs a condition the
vendor will not produce on demand. A bad request — wrong content type,
unknown field, bad id — gets the vendor's real error with no setup. Anything
else is a `faults` row on the sandbox:

```http
POST {control_url}/veris/data
{"data":{"faults":[{"method":"POST","path":"/v3/company/123/invoice","outcome":"hang","phase":"after","remaining":1}]}}
```

```json
{"data":{"faults":[{"method":"POST","path":"/v1/charges","outcome":"error","error":{"status":429,"code":"<listed-code>","headers":{"Retry-After":"2"}},"remaining":2}]}}
{"data":{"faults":[{"method":"POST","path":"/v1/charges","latency_ms":8000}]}}
```

`outcome: "error"` requires an `error` object; a row that sets one without
the other is refused. A slow-but-normal response is `latency_ms` with **no**
`outcome` — the second row above.

| the report says | the row |
|---|---|
| the response never came back, but the write happened | `hang` (or `error` with a 5xx) with phase `after` — the committed-but-unanswered write |
| we got throttled | `error 429`, `remaining 2`: two matching requests are throttled, then responses resume; not an upstream quota window |
| the vendor refused | `error <status>` with a status **the manual lists** — an unlisted one is refused with `422` naming the allowed set |
| it was slow enough to time out | `latency <ms>` |
| the request was lost before the write | `hang` with phase `before` |

- `path` is the vendor request path without scheme, host, query or
  fragment; copy it from `GET {control_url}/veris/requests` when an SDK hides
  it. A dynamic segment can be a `{name}` template instead of a concrete
  value — `/v1/payment_intents/{id}/confirm` matches every id, and binds
  `path.id` for `match` to narrow on. One templated row beats a row per id,
  and it is the only way to arm a fault before the id exists.
- **An SDK may spend the fault before your code sees it.** Most vendor clients
  retry `>=500` and connection errors internally, reusing the caller's
  idempotency key; a Stripe Node client was measured doing exactly this in a
  benchmarked run, absorbing an armed `500` inside a single call so it never
  reached the code under test — which reads as the bug not reproducing. If an
  armed failure vanishes, check the client's retry setting before doubting the
  fault, and arm a class the SDK does not retry (a `4xx`, e.g. `429`) to isolate
  the behaviour you actually mean to exercise.
- `remaining 1` spends the fault once. Delete persistent faults in cleanup:
  `DELETE {control_url}/veris/data` with the row's id.
- A row can also carry `match` on body, query or path fields
  (`{"body.resource_id":"…"}`, `{"query.expand":"items"}`,
  `{"path.id":"pi_123"}`; the manual lists the keys a service supports),
  `error.code`, `error.headers`,
  `{"status":502,"raw":true}` for a non-JSON gateway response, and
  `idempotency: "bind"|"unbound"` for whether an error replays on key reuse —
  `bind` is only accepted on a `phase: before`, `outcome: error` row with no
  `raw`, since nothing else produces a response the key can store:
  ```http
  POST {control_url}/veris/data
  {"data":{"faults":[{"method":"POST","path":"/vendor/path",
    "match":{"body.resource_id":"test-owned-id"},
    "outcome":"error","error":{"status":429,"code":"<listed>","headers":{"Retry-After":"2"}},
    "remaining":2}]}}
  ```

## A GraphQL service

Every request is one `POST /graphql`, so a row with that path and no `match`
fires on all of them — usually not what a test wants. Narrow to the
operation, and to its variables, the same way:

```http
POST {control_url}/veris/data
{"data":{"faults":[{"method":"POST","path":"/graphql",
  "match":{"graphql.operation":"issueCreate"},
  "outcome":"error","error":{"status":429,"code":"<listed>"},"remaining":1}]}}
```

`graphql.operation` is the root field the request executes;
`graphql.variables.<path>` narrows further. The manual lists which of these
a service supports.

## Then drive the real code through it

A fault proves nothing until the application's own code path meets it: the
endpoint, worker, job or handler the task names — not a curl standing in for
it. Arm the row, run that path under `veris-proxy` ([proxy.md](proxy.md)),
then read the ledger: `GET {control_url}/veris/data?entity_type=<table>` shows whether
the write landed, and `GET {control_url}/veris/requests` shows what the client did next. That
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
one from `GET {control_url}/veris/data?entity_type=oauth_tokens`; never insert tokens by hand.

Some services do not judge credentials themselves — they verify what a
companion identity service in the same environment minted. There the values
are always checked and this row does not change acceptance, so arming it and
seeing no difference is the design, not a broken sandbox. The `auth` table's
own description in `GET {control_url}/veris/schema` says which kind a
service is; read it before concluding anything from an unchanged result.

## The clock

One `clock` row is shared by every service in the sandbox:

```http
PATCH {control_url}/veris/data
{"data":{"clock":[{"id":1,"offset_seconds":2678400}]}}
```

It advances vendor time — expiry, retention, replay windows. Advance the
application's own test clock separately; never move it backwards during a
suite.

`mode` is `live` by default, where `offset_seconds` is added to real time.
Setting `mode` to `frozen` with a `frozen_time` (unix epoch seconds) stops
vendor time at that instant, which is what makes a retention or expiry
boundary reproducible instead of racing wall time:

```http
PATCH {control_url}/veris/data
{"data":{"clock":[{"id":1,"mode":"frozen","frozen_time":1793491200}]}}
```

Either way, the sandbox's clock is the only one that moves. A test that
signs tokens or verifies signatures has to keep the application's clock — or
the moment it mints the token — in step with it, or the skew becomes the
result. And moving the clock can expire the credential you are holding:
re-authenticate and measure again rather than reading that 401 as the
vendor's answer.
