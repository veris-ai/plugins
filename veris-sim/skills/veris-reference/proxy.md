# The run: the application's own code against the twin

Read this to exercise the change, and to know what a green proves.
`veris-proxy` puts the application's unmodified code — production hostnames,
credentials, client stack — in front of the sandbox by rerouting its outbound
HTTP(S) from outside the process, and ends with a **receipt** of what the
sandbox received. Vendor MCP servers are supported for the services that list
one (the service catalog shows which); keep the production MCP URL. `.veris/run.sh` carries the command; `/veris-sim:setup`
wrote it. Flags before `--` pass through; a command after `--` replaces the
recorded default:

```
.veris/run.sh                                  the recorded test command
.veris/run.sh --strict                         extra flags pass through
.veris/run.sh -- pytest -x tests/integration/test_one.py
```

With `VERIS_SANDBOX_ID` set, the run attaches to that sandbox and leaves it
running — set it to the task's sandbox, so the faults armed and the state
read back are the ones the code met. Unset, each run deploys a fresh sandbox
of the environment, runs the command, prints the receipt, deletes the
sandbox; it logs `sandbox ready sandbox_id=<id>`, and `get_sandbox` with that
id returns each service's `control_url` for as long as the run lives. To seed
or arm inside a run of that kind, start a session and work inside it:

```
.veris/run.sh -- sleep infinity &
docker exec "$(docker ps -q -f name=veris-workload-)" bash -lc '<one pass>'   # as often as needed
kill %1                                                                        # ends the run, prints the receipt for the whole session
```

| flag | what it does |
|---|---|
| `--sandbox <id>` (or `VERIS_SANDBOX_ID`) | attach to a sandbox that exists — the task's — and leave it; never together with `--environment` |
| `--environment <id>` | a sandbox per run, deleted after; `--ttl-minutes` bounds one that outlives a crashed run |
| `--require-service <name>[:count]`, `--require-host <host>[:count]` | makes a service, host, or call count the verdict |
| `--strict` | a request to an unmapped host is answered `502` naming the host instead of reaching the real internet — the claim "the code reached nothing but the sandbox" |
| `--route <service>=<host>[/prefix]` | routes a service at a hostname the embedded table does not know — a regional or custom endpoint |
| `--cap-add <CAP>` | every capability is dropped; an entrypoint that switches users (`su`, `gosu`) needs `SETUID` and `SETGID`. `ALL` and `SYS_ADMIN` are refused |
| `--patch-bundled-cas` | SDKs that refuse the proxy's certificate quietly — stripe, older botocore, httplib2 — [trust.md](trust.md) |
| `--expose <port>` | a public URL for the application to receive callbacks — [webhooks.md](webhooks.md) |
| `--keep-proxy` | leaves the proxy container up for inspection |

Exit codes: the command's own; `3` — the run never proved its traffic (empty
receipt, an unmet `--require-*`, or every TLS handshake to a mapped host
rejected, with a diagnostic naming the next step); `4` — indeterminate.

## What a green proves

A green and a receipt prove the change only together, and only from the same
run:

- the receipt names the service the tests were meant to reach — it counts
  every completed request to a mapped vendor host, setup traffic included;
  the paths in `GET {control_url}/veris/requests` say whose it was;
- the run executed the changed code on its way to the vendor: a flow from the
  boundary the task names, with the call the report describes, unchanged. A
  green earned by changing the caller's call proves the caller changed;
- the same flow red before the change and green after it is the strongest
  form;
- nothing in the repository or its environment was pointed at a sandbox.

A green suite with an empty receipt is not a pass; a red suite whose receipt
shows the traffic arrived is a real integration finding —
[troubleshooting.md](troubleshooting.md) reads the signals. A certificate or
connection error against a mapped host is an SDK that bundles its own CA —
[trust.md](trust.md). Only the second-worst outcome is silent: a run whose
SDK calls all failed TLS still prints a healthy receipt if anything else in
the run completed a request on that host; read the paths.

## Sandbox state

An environment's default state is usable without preparation; what a case
needs beyond it is seeded through `/veris/data` in the run, and state worth
keeping is kept as snapshots — [state.md](state.md). Never promote from a
command: promote re-pins the environment every later run boots from.
