# SDKs that bundle their own CA

The kernel redirect moves the *traffic* below every library, but *trust* is
still decided inside the process. An SDK that ships its own CA bundle and
hands it straight to the TLS layer — stripe-python and stripe-ruby, older
botocore, httplib2 — reads none of the trust environment and refuses the
proxy's certificate even though routing worked.

## The symptom

`CERTIFICATE_VERIFY_FAILED`, `SSLError`, "unable to get local issuer
certificate", or a generic connection error against a *mapped* host while
other services intercept fine. stripe-python hides the cause as
`APIConnectionError` ("Network error: A ConnectError was raised" / "Could not
verify Stripe's SSL certificate"), so any connection-shaped SDK error against
a mapped host may be this.

## What the proxy prints

When a mapped host rejected every handshake and completed no request, the run
fails with one line:

    <host>: N TLS handshake(s) rejected (<reason>) after the certificate was
    minted; 0 requests completed -- the client refused the interception CA,
    likely an SDK-bundled CA bundle or certificate pinning

A softer variant — "handshake(s) ended after the certificate was minted …
not certain" — appears when the connection closed without a TLS alert and
does not fail the run.

**A host that completed any request gets no diagnostic.** The receipt counts
completed requests per mapped host and the check skips a host with a count
above zero, so a run whose SDK calls all failed TLS can still print a healthy
receipt if something else in the run — a health check, a second client —
completed a request on that host. When the SDK reports a connection error but
the receipt shows traffic for its host, read the paths in
`{control_url}/veris/requests` to see whose traffic it was.

## The fix

On a sandbox whose gateway intercepts egress (`.veris/session.md` names it),
the symptom is the same and none of the remedies below exist: the run command
is not `veris-proxy run`, so there is no `-v` mount and no
`--patch-bundled-cas`. The SDK cannot reach the twin from here. Report it as
the Gate-1 outcome rather than patching the client.

1. **`--patch-bundled-cas`** on the run command. It scans the image and the
   `-v` mounts for the bundles it knows — pip's vendored certifi, certifi,
   botocore, stripe, httplib2 — and for any file named `cacert.pem`,
   `ca-certificates.crt` or `cacerts.txt` that validates as a CA bundle,
   appends the Veris CA to a copy of each, and over-mounts the copy read-only
   over its own path. The SDK keeps loading its own bundle through its own
   code path; the file just carries one more root. It logs one line per file
   it patched. It does not report files it could not patch. Add the flag up
   front when the dependency set names one of these SDKs; it costs nothing
   when there is nothing to patch.
2. **Over-mount by hand** when the diagnostic persists: find the SDK's bundled
   CA file in the image or the bind-mounted venv or `node_modules`, copy it
   out, append the Veris CA, and mount the copy back over the original with
   `-v "$PWD/.veris-trust/patched.crt:/exact/container/path:ro"`. The CA to
   append: each run's proxy mints its own and publishes it inside the
   workload at `/veris-share/veris-ca.pem`, so bind the file writable and
   append it as the run's first step
   (`-- sh -c 'cat /veris-share/veris-ca.pem >> /path; <tests>'`); on the
   host tier it is `~/.veris/ca/veris-ca.pem`. Append, never replace: a file
   holding only the Veris CA breaks the SDK's real-vendor trust for every
   passthrough host. This is trust data, not code.
3. **No bundled CA file anywhere** means the SDK pins — SPKI hashes or
   certificate fingerprints (OkHttp `CertificatePinner`, curl
   `--pinnedpubkey`, aiohttp `fingerprint=`, urllib3 `assert_fingerprint`):
   a second comparison after chain validation that no added root can satisfy.
   Stop and report it to the user.

A JVM client that reads a JKS truststore takes its trust from there: build
one containing the Veris CA and pass `--java-truststore <path>`
(`--java-truststore-pass` when it is not `changeit`).

Never set the SDK's CA or verify options in test code, monkey-patch `ssl`, or
disable verification: each modifies the code path under test.

## A container the run did not start

The over-mount and the trust environment reach only the workload container
the proxy starts. A compose service that joins the proxy's network namespace
(`network_mode: "container:veris-proxy-…"`) — an API server, a worker, any
sidecar that is the process actually calling vendors — shares the kernel
redirect but not the trust: every vendor call dies (`SELF_SIGNED_CERT_IN_CHAIN`
in Node) while the workload looks healthy and the receipt shows nothing for
that service. Hand the sidecar the trust environment:

1. Find the share:
   `docker inspect -f '{{range .Mounts}}{{if eq .Destination "/veris-share"}}{{.Source}}{{end}}{{end}}' <veris-proxy-container>`
2. Give the sidecar `env_file: <share>/veris.env` (or `--env-file`) and a
   volume `<share>:/veris-share`; the env file points every runtime's CA
   variable (`NODE_EXTRA_CA_CERTS`, `SSL_CERT_FILE`, …) at
   `/veris-share/veris-ca.pem`.

The share is minted per run, so wire these through variables rather than a
hardcoded path; `--keep-proxy` keeps the share alive for inspection.
