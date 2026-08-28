# Troubleshooting

What each signal means. Most suspected sandbox bugs turn out to be in the
test setup, and the evidence to tell them apart is already recorded.

| signal | what it says |
|---|---|
| the receipt | completed requests per mapped vendor host and service. A green suite with an empty receipt is not a pass; a red suite whose receipt shows the traffic arrived is a real integration finding. `/veris/*` reads at `control_url` are not on a mapped host and never appear in it; the suite's own setup traffic at a vendor hostname does |
| `GET {control_url}/veris/requests` | the wire trace of every request and response (the query string is not recorded yet). The failing exchange can be replayed from it with curl before the sandbox, the proxy, or the code is blamed. Ask for the tier the evidence is on — see below |
| `GET {control_url}/veris/data?entity_type=<name>` | what the vendor stored — the row a create produced, the replay it recorded, the state a callback left |

## An empty receipt

The run exits 3 on its own when an `--environment` run sent the sandbox
nothing — deploying a sandbox for a suite that never called it is a failure,
not a pass. Causes worth checking, in order: the suite genuinely never calls
its dependency (mocks still active, tests filtered out); the traffic went to
the real vendor because the host is not in the environment's service map; or
TLS trust failed inside the workload ([trust.md](trust.md)) so no request ever
completed.

## Which tier holds the evidence

`?tier=` narrows the trace, and the right value depends on what you are
proving:

| you want | ask |
|---|---|
| ordinary traffic the application sent | `tier=handler` |
| the exchange an armed fault produced | `tier=fault` |
| a fault and the retry after it | both, separately — or one bounded unfiltered page, dropping `control` rows |

`tier=control` is your own `/veris/*` seeding and read-back. It is recorded
like anything else, so an unfiltered page after a heavy seed can be mostly
your own writes — which reads as "the application sent nothing" when it
sent plenty. `tier=handler` is **not** the universal read-back: a gate that
reproduces a failure is usually looking at `tier=fault`, and a gate proving
recovery usually needs both.

## Vendor-shaped errors

- A vendor-shaped `4xx`: read the response and `/veris/requests`. It is
  usually the real error for the request you sent.
- A refusal that **names itself unsupported** — typically a `501`, in the
  vendor's own error shape — is conclusive. The twin does not model that
  surface: another endpoint, another header, another API version returns the
  same. Record it for the user, design around what the twin does model, and
  stop probing. Do not build on ids or fragments of the missing surface that
  appear stamped on other rows, and never change correct production client
  behaviour to work around it.
- **An ordinary `400` or `404` is inconclusive**, and a service may answer a
  coverage gap with one. It is indistinguishable from the vendor's own
  answer, so it is not evidence of a gap on its own. Before reading anything
  into it, confirm the request's credentials, API version, payload shape,
  and the rows it depends on being seeded. With those known good, one
  further controlled probe is worth it. If the answer is still ambiguous,
  report it as *"possible twin coverage gap; indistinguishable from vendor
  behavior"* and stop. Never assert a coverage gap the available evidence
  cannot separate from real vendor behavior — and do not read one off
  `/veris/schema` either: the schema describes the state a sandbox holds,
  not the operations the service answers.

  **But coverage is answerable, and not by reading a `404`.** Arm a fault at the
  operation in question: the fault validator checks it against the same published
  surface `/veris/operations` would list, and says so in words — *"does not match
  a published operation of this service"*, or *"… is not published for path …;
  allowed methods: [...]"*, or it accepts. Both doors are in [twin.md](twin.md).
  That is a control-plane answer and it settles the question; the vendor-shaped
  `404` above never will. Put what you establish in `.veris/NOTES.md` so the next
  task does not pay for it again.
- A bare `500`: capture the request and the trace as a sandbox defect.
- Widespread `502`: check sandbox status and expiry.
- A timeout: check armed faults, whether the request reached the trace, and
  the client's per-request timeout — an error path can be much slower than a
  success path.
