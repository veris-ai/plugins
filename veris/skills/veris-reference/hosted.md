# Hosted tier: the code runs in a hosted box wired to the twin

An OpenCode plugin that already manages this session uses [session.md](session.md)
instead. This hosted-runner recipe owns a separate test sandbox from the host.

Use this tier when the engineer asks to run the tests on a hosted machine, or when
the code needs traffic redirection and the machine cannot run Docker. The host tier
without `--image` is not a fallback for code under test.

Here the tests run in a hosted box whose outbound proxy is the twin's gateway. Calls
to the vendor hostnames the plane serves are routed to the twin from outside the
process. The code stays unmodified and keeps its production hostnames, credentials
and client stack, exactly as under `veris run`. The hosted box runs the code; the twin
that `veris up` made answers its service calls. They are separate resources. Run
`veris` on the controlling machine: bring up the twin, seed it, arm faults, set its
clock, read its trace and stored rows, and tear it down from there. Only the test
workload and its dependency installation move into the hosted box.

This recipe provisions a separate test box owned by the task. A session whose
OpenCode plugin already owns a sandbox has a different lifecycle; do not adopt or
delete that session's box through this recipe.

## Choosing it

An explicit request to run remotely selects this tier even when Docker works. In
the absence of that request, apply the code's direct-tier gate in
[direct.md](direct.md) first. If the code needs redirection, use the container tier
when Docker is available; use hosted when `veris doctor` reports missing or
unavailable Docker and nobody can start a daemon here.

Two more doctor lines gate it. The gateway line must read `Gateway mode configured`:
the box routes through the plane's gateway, and a plane that prints `Gateway mode not
configured` cannot serve one. The login line stays as it is.

## Provider recipe

Read the provider's prerequisites, run steps and limitations before `veris up`.
Check its runner and credentials first so no twin waits while they are obtained.
The provider documented here is Daytona:

| provider | recipe |
|---|---|
| Daytona | [daytona.md](daytona.md): installation, keys, exact commands, certificate setup, network limits and sandbox deletion |

Follow that recipe to provision a box on the task's twin, upload the code, install
dependencies, prepare certificate trust and run the test command. Use the receipt
rule below to decide what the run proved. Provider commands and capabilities belong
in the recipe; `veris run` flags do not configure a separate runner.

## Prepare the remote workload

The provider must be able to resolve the image or snapshot. A tag built only in the
local Docker daemon is not available remotely. Choose a provider-accessible image
with the required runtime and tools; the provider recipe names its image options.
If the runtime must be installed, include it in the image or upload a compatible
standalone runtime with the code. Check download hosts before provisioning, because
the provider may fix its network allowlist at creation. Install the runtime and
dependencies before patching their certificate bundles.

Local mounts and files are not visible in the box. Upload the source and any
credential files the application needs, using the twin's credential rules from
setup. Keep those files out of git and upload only what this workload needs; the
provider's upload exclusions determine what is sent. A local path in `.veris/NOTES.md`
must be replaced by its path inside the box. Set a path containing `$PWD` or `$HOME`
inside the remote shell command: a provider's `--env KEY=VALUE` value is literal.
After editing source locally, upload the changed code before rerunning the flow;
an execution command alone does not synchronize the working tree.

Account for any database or other process the tests need before creating the box.
Use the twin's supplied data-plane connection where applicable, or prepare those
processes in the remote workload. A local service or Docker Compose stack does not
move with the source upload.

## The receipt

There is no `veris run` here, so there is no receipt line, no two ledgers and no
`--require-service` verdict. The twin's trace is the receipt, the way it is in the
direct tier. Before the test flow, note the newest entry for the required twin:

```
veris sandbox trace --service <twin> --limit 1 --json
```

A successful read returning `[]` means the watermark is `0`; read back with
`--since 0`. A failed read is not an empty trace: fix that failure before running.
Trace ids are each twin's own sequence, so take a watermark per required twin after
provisioning and preparation, immediately before the test flow.

After it, read `veris sandbox trace --service <twin> --since <id>` and
`veris sandbox data get <twin> <table>` on the controlling machine. `handler` entries
show handled application calls; `fault` entries show exchanges intercepted by an
armed fault and also count as application traffic. `control` entries are admin
operations such as seeding and read-back; `delivery` entries are callbacks. Neither
substitutes for the application's outbound call. Use `--tier handler` or `--tier
fault` to inspect the relevant traffic, and `--body <entry-id> --service <twin>`
when the request and response are needed to establish the outcome.

**Done when the trace shows at least one entry from this test flow for the required
twin, and the stored state or response shows the outcome being tested.** Provisioning
probes and control operations do not prove the application ran. No entries means the
run proved nothing, whatever the test command printed: the same finding as an exit 3,
and the causes are the same, in the same order —
[troubleshooting.md](troubleshooting.md), *An empty receipt, exit 3*. Never fix an
empty trace by changing the call or its base URL.

## What goes in the files

`.veris/twin.yaml`: no `--image` on `veris env create`, so `proxy.image` stays unset;
the other proxy flags have no run to act on here, so leave them out too.

`.veris/NOTES.md`, under *How to run*: name the provider, pin the runner's published
package version and full invocation, and record the actual
provisioning command with its image and network options, code upload, dependency
install, certificate preparation, test command and teardown. Include the watermark
read and the trace entry that proved the first real call, with its id, which
[direct.md](direct.md) calls *The trust anchor*. `build` and `fix` take their run
lines from here.

## Cleanup

Save the evidence before deleting either resource. When the task is done, delete the
hosted box with the provider's teardown command, then `veris down` for the twin.
The resources have separate lifetimes: provisioning a box does not extend the twin's
TTL, and `veris down` does not delete the box. The provider recipe specifies deletion
permissions and any automatic expiry; use explicit teardown when the task is done.
