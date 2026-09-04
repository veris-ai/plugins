# Hosted tier: the code runs in a hosted box wired to the twin

The container tier needs a Docker daemon, and a cloud dev box usually has none.
`veris doctor` says so on its Docker line: `! docker not on PATH — host tier works;
--image (container tier) will not`, or a daemon that does not answer. The host tier is
not a fallback for code under test, so without this tier such a machine has no path.

Here the tests run in a hosted box whose outbound proxy is the twin's gateway. Calls
to the vendor hostnames the plane serves are routed to the twin from outside the
process. The code stays unmodified and keeps its production hostnames, credentials
and client stack, exactly as under `veris run`. The hosted box runs the code; the twin
that `veris up` made answers its service calls. They are separate resources.

## Choosing it

Decide from `veris doctor`, never from the code. The direct-tier gate in
[direct.md](direct.md) comes first, because it is about the code; when the code fails
that gate and doctor's Docker line is `!` and nobody can start a daemon here, this is
the tier. When Docker answers, the container tier is the tier, and this file does not
apply.

Two more doctor lines gate it. The gateway line must read `Gateway mode configured`:
the box routes through the plane's gateway, and a plane that prints `Gateway mode not
configured` cannot serve one. The login line stays as it is.

## Provider recipe

Read the provider's prerequisites, run steps and limitations before provisioning.
Daytona is the currently supported provider:

| provider | recipe |
|---|---|
| Daytona | [daytona.md](daytona.md): installation, keys, exact commands, certificate setup, network limits and sandbox deletion |

Follow that recipe to provision a box on the task's twin, upload the code, install
dependencies, prepare certificate trust and run the test command. Use the receipt
rule below to decide what the run proved. Provider commands and capabilities belong
in the recipe; `veris run` flags do not configure a separate runner.

## The receipt

There is no `veris run` here, so there is no receipt line, no two ledgers and no
`--require-service` verdict. The twin's trace is the receipt, the way it is in the
direct tier. Before the test flow, note the newest entry for the required twin:

```
veris sandbox trace --service <twin> --limit 1 --json
```

After it, `veris sandbox trace --service <twin> --since <id>` is what this run sent,
and `veris sandbox data get <twin> <table>` is what the twin stored. Trace ids are each
twin's own sequence, so the watermark is per twin.

**Done when the trace shows at least one entry from this test flow for the required
twin.** Provisioning probes do not prove the application ran. No entries means the
run proved nothing, whatever the test command printed: the same finding as an exit 3,
and the causes are the same, in the same order —
[troubleshooting.md](troubleshooting.md), *An empty receipt, exit 3*. Never fix an
empty trace by changing the call or its base URL.

## What goes in the files

`.veris/twin.yaml`: no `--image` on `veris env create`, so `proxy.image` stays unset;
the other proxy flags have no run to act on here, so leave them out too.

`.veris/NOTES.md`, under *How to run*: name the provider and record the actual
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
