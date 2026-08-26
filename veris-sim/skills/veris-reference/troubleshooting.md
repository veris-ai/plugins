# Troubleshooting

What each signal means. Most suspected sandbox bugs turn out to be in the
test setup, and the evidence to tell them apart is already recorded.

| signal | what it says |
|---|---|
| the receipt | completed requests per mapped vendor host and service. A green suite with an empty receipt is not a pass; a red suite whose receipt shows the traffic arrived is a real integration finding. `/veris/*` reads at `control_url` are not on a mapped host and never appear in it; the suite's own setup traffic at a vendor hostname does |
| `GET {control_url}/veris/requests` | the wire trace of every request and response (the query string is not recorded yet). The failing exchange can be replayed from it with curl before the sandbox, the proxy, or the code is blamed |
| `GET {control_url}/veris/data?entity_type=<name>` | what the vendor stored — the row a create produced, the replay it recorded, the state a callback left |

## An empty receipt

The run exits 3 on its own when an `--environment` run sent the sandbox
nothing — deploying a sandbox for a suite that never called it is a failure,
not a pass. Causes worth checking, in order: the suite genuinely never calls
its dependency (mocks still active, tests filtered out); the traffic went to
the real vendor because the host is not in the environment's service map; or
TLS trust failed inside the workload ([trust.md](trust.md)) so no request ever
completed.

## Vendor-shaped errors

- A vendor-shaped `4xx`: read the response and `/veris/requests`. It is
  usually the real error for the request you sent.
- `feature_not_supported`: the twin does not model that surface, and the
  manual (`GET {control_url}/veris/manual`) already says so. One such answer
  is final — another endpoint, another header, another API version returns
  the same. Record it for the user and design around what the twin does
  model; do not build on ids or fragments of the missing surface that
  appear stamped on other rows.
- `501` from a vendor path: a sandbox coverage gap. Record it for the user;
  do not change correct production client behaviour to work around it.
- A bare `500`: capture the request and the trace as a sandbox defect.
- Widespread `502`: check sandbox status and expiry.
- A timeout: check armed faults, whether the request reached the trace, and
  the client's per-request timeout — an error path can be much slower than a
  success path.
