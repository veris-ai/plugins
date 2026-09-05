# Troubleshooting

For a verified plugin-managed session, start with [session.md](session.md) and
[opencode.md](opencode.md). Preserve the provider's trust configuration; the
container/proxy remedies below apply to CLI-owned execution.

What each signal means. Most suspected sandbox bugs turn out to be in the test setup,
and the evidence to tell them apart is already recorded.

| signal | what it says |
|---|---|
| the receipt from `veris run` | completed requests per twin, two counts: what the proxy saw leave the app (`the sandbox received N request(s)`) and what the sandbox recorded (`the sandbox recorded N request(s) since the watermark`), then the verdict line (`✓ required <twin> ≥1: saw N   ✓ ledgers agree (N = N)`; `! ledgers differ` when they do not). A requirement passes when either count meets it; a `✓` one side alone decided says which, `(engine; …)` or `(sandbox ledger; not proxied)`. A green suite with an empty receipt is not a pass; a red suite whose receipt shows the traffic arrived is a real integration finding. Your own `veris sandbox` reads never count: the counts are taken since a watermark the run sets, and any `/veris/*` reads that fall inside the run appear on a separate `control-plane (/veris/*)` line marked not counted. The suite's own setup traffic at a vendor hostname does count. `--receipt <file>` keeps it as JSON |
| `veris sandbox trace` | the wire trace of every request and response. The failing exchange can be replayed with curl before the sandbox, the proxy or the code is blamed. Ask for the tier the evidence is on |
| `veris sandbox data get <twin> <table>` | what the vendor stored: the row a create produced, the replay it recorded, the state a callback left |

## An empty receipt, exit 3

`veris run --fresh` exits 3 on its own when the run sent the sandbox nothing:
deploying a sandbox for a suite that never called it is a failure, not a pass. A run
against this folder's sandbox exits 3 when a `--require-*` is unmet. Causes, in
order:

1. The suite genuinely never calls its dependency: an in-process mock still active,
   the tests filtered out. Pick a test that does.
2. The traffic went to the real vendor because the hostname is not one of the
   environment's twins. `veris services` lists the catalog, `veris env get` the
   environment. `--strict` turns that leak into a refusal.
3. TLS trust failed inside the workload, so no request ever completed. Next section.
4. The control plane serves no vendor hostname for the twin, so nothing was
   intercepted and its URL was handed to the app instead (`veris: stripe: not proxied;
   handed STRIPE_API_BASE=…`). `veris doctor`'s vendor-hostnames line names every twin
   in that state; a data plane (postgres, yente) there is by design, an ordinary
   vendor twin is not. `--route <twin>=<host>` supplies the hostname for a run.
5. The vendor call comes from a process the run did not start. Last section.

Never fix an exit 3 by changing the call or its base URL.

## Which tier holds the evidence

`veris sandbox trace --tier` narrows the trace, and the right value depends on what
you are proving:

| you want | ask |
|---|---|
| ordinary traffic the application sent | `--tier handler` |
| the exchange an armed fault produced | `--tier fault` |
| a fault and the retry after it | both, separately, or one bounded unfiltered page dropping `control` rows |

`control` is your own seeding and read-back. It is recorded like anything else, so an
unfiltered page after a heavy seed can be mostly your own writes, which reads as "the
application sent nothing" when it sent plenty. `handler` is not the universal
read-back either: a gate that reproduces a failure is usually looking at `fault`, and
a gate proving recovery usually needs both.

## An SDK refuses the proxy's certificate

The proxy redirects traffic below every library, but trust is decided inside the
process. Some SDKs ship their own CA bundle and hand it straight to the TLS layer:
Stripe's Python and Ruby clients, older botocore, httplib2. Such an SDK reads none of
the trust environment, and it refuses the proxy's certificate even though routing
worked.

Symptoms: `CERTIFICATE_VERIFY_FAILED`, `SSLError`, "unable to get local issuer
certificate", or a generic connection error against a twin's host while other twins
intercept fine. Stripe's Python client hides it as `APIConnectionError` ("Could not
verify Stripe's SSL certificate"), so any connection-shaped SDK error against a twin's
host may be this.

When a host rejected every handshake and completed no request, the run fails with
one line: `<host>: N TLS handshake(s) rejected (<alert>) after the certificate was
minted; 0 requests completed -- the client refused the interception CA.` followed by
a `Next:` step. Follow the `Next:` step; it is computed from what the run already
tried. A softer `<host>: N TLS handshake(s) ended after the certificate was minted;
0 requests completed -- CA rejection or certificate pinning is likely ... not
certain` appears when the connection closed without a TLS alert (Node does this). It
does not fail the run unless the whole receipt is empty; then it does.

A host that completed some requests and also rejected handshakes gets a non-fatal line:
`rejected ... even though N request(s) completed -- another client in this run refused
the interception CA`. Two clients disagreed about the CA. The one that completed may be
a health check or a second client rather than the code under test. So when the SDK
reports a connection error but the receipt shows traffic for that host, read the
trace's paths to see whose traffic it was.

The fix, in order:

1. `veris run --patch-bundled-cas`. It scans the image and the `-v` mounts for the
   bundles it knows: pip's vendored certifi, certifi, botocore, stripe for Python and
   Ruby, httplib2. It appends the proxy's certificate to a copy of each, and mounts
   that copy read-only over the original. The SDK keeps loading its own file; it just
   carries one more root. It prints one line per file over-mounted, one per file that
   already carried the certificate, and a count; nothing for files it does not know.
   A CA-bundle-shaped file outside that table (named `cacert.pem`,
   `ca-certificates.crt`, `cacerts.txt`, `ca-bundle.crt`, `ca-bundle.pem` or
   `cert.pem`) is **not** patched; when a host then rejects every handshake, the
   failure line names it (`CA-bundle-shaped file(s) the scan does not know: ...`) for
   step 3. Add the flag up front when the dependency set names one of these SDKs; it
   costs nothing when there is nothing to patch.
2. A JVM client reads a JKS truststore: build one containing the proxy's certificate
   and pass `--java-truststore <path>` (`--java-truststore-pass` when it is not
   `changeit`).
3. Over-mount by hand when the line persists. Find the SDK's bundled CA file in the
   image, in the mounted venv or in `node_modules`; the failure line names the
   candidates. Copy it out, append the proxy's certificate, and mount the copy back
   over the original with `-v "$PWD/.veris-trust/patched.crt:/exact/container/path:ro"`.
   Each run's proxy mints its own certificate and publishes it inside the workload at
   `/veris-share/veris-ca.pem`; on the host tier it is `~/.veris/ca/veris-ca.pem`. So
   bind that file writable and append it as the run's first step:
   `-- sh -c 'cat /veris-share/veris-ca.pem >> /path; <tests>'`. Append, never replace:
   a file holding only the proxy's certificate breaks the SDK's trust for every real
   host.
4. No bundled CA file anywhere means the SDK pins: it checks SPKI hashes or certificate
   fingerprints. OkHttp's `CertificatePinner`, curl's `--pinnedpubkey`, aiohttp's
   `fingerprint=` and urllib3's `assert_fingerprint` all do this. Pinning is a second
   check after chain validation, and no added root can satisfy it. The failure line
   says so when `--patch-bundled-cas` covered every known bundle and no other
   bundle-shaped file exists. Stop and report it; retrying will not change it.

Never set the SDK's CA or verify options in test code, monkey-patch `ssl`, or disable
verification: each modifies the code path under test.

## Vendor-shaped errors

- A vendor-shaped 4xx: read the response and the trace. It is usually the real error
  for the request you sent.
- A refusal that names itself unsupported, typically a 501 in the vendor's own error
  shape, is conclusive: the twin does not model that surface, and another endpoint,
  header or API version returns the same. Record it for the engineer, design around
  what the twin does model, and stop probing. Do not build on ids or fragments of the
  missing surface that appear on other rows, and never change correct production
  client behaviour to work around it.
- An ordinary 400 or 404 is inconclusive; a twin may answer a coverage gap with one,
  and it is indistinguishable from the vendor's own answer. Before reading anything
  into it, confirm the request's credentials, API version, payload shape, and that
  the rows it depends on are seeded. A setting row the twin booted with counts as one
  of those, and `veris sandbox data set` changes it. With those known good, one
  further controlled probe is worth it. Still ambiguous: report it as "possible twin
  coverage gap; indistinguishable from vendor behaviour" and stop. Never assert a gap
  the evidence cannot separate from vendor behaviour, and do not read one off the
  schema: the schema describes the state a sandbox holds, not the operations it
  answers. Coverage is answerable, and not by reading a 404: the twin's operations list
  ([twin.md](twin.md)) is a control-plane answer that settles it. Put what you
  establish in `.veris/NOTES.md` so the next task does not pay for it again.
- A bare 500: capture the request and the trace as a sandbox defect.
- Widespread 502: `veris status`; the sandbox may have expired.
- A timeout: check armed faults (`veris sandbox data get <twin> faults`), whether the
  request reached the trace, and the client's own per-request timeout; an error path
  can be much slower than a success path. Remove one left armed from an earlier probe
  with `veris sandbox data delete <twin> faults id=<fault id> --yes`.

## The agent is sandboxed

Symptoms, on a machine where the engineer says the network and Docker both work:
`veris doctor` prints `✗ … dial tcp: lookup svc.api.veris.ai: no such host` for the
control plane and `! docker on PATH but docker info failed: permission denied … docker.sock`;
or, past setup, `veris up` fails with the same `no such host`; or every `veris` and
`docker` command waits on an approval before it runs.

The cause is not the machine. The agent's own sandbox has no network and no Docker
socket, so nothing here can reach the control plane or the daemon, and a policy that
escalates per command turns each one into a wait. Nothing in these skills can lift
that; only the engineer can, by restarting the agent with network and Docker access
— the install notes for their client say how — and running the command again.

Say so and stop. Do not retry, do not work around it with the direct tier, and do not
read the two lines as a broken install: `veris doctor` on the engineer's own shell
will show everything green.

## A container the run did not start

The over-mount and the trust environment reach only the workload container that
`veris run` starts. Another container can share the redirect without sharing the
trust: an API server, a worker, or any compose service that joins the proxy's network
namespace with `network_mode: "container:veris-proxy-…"`. When such a sidecar is the
process actually calling the vendor, every vendor call from it dies —
`SELF_SIGNED_CERT_IN_CHAIN` in Node — while the workload looks healthy and the receipt
shows nothing for that twin. The run's TLS failure
line ends with a note about exactly this ("A sibling container this run did not
start ... never receives the trust handoff"). Hand the sidecar the trust environment:

1. Find the share. The proxy container is named `veris-proxy-<pid>`:
   `docker inspect -f '{{range .Mounts}}{{if eq .Destination "/veris-share"}}{{.Source}}{{end}}{{end}}' <veris-proxy-container>`
2. Give the sidecar `env_file: <share>/veris.env` (or `--env-file`) and a volume
   `<share>:/veris-share`; the env file points every runtime's CA variable
   (`NODE_EXTRA_CA_CERTS`, `SSL_CERT_FILE`, and the rest) at `/veris-share/veris-ca.pem`.

The share is minted per run, so wire these through variables rather than a hardcoded
path; `--keep-proxy` keeps the share alive for inspection.
