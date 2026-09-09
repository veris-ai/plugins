# Veris plugins

Veris runs stateful twins of the external services an application calls. An
**environment** names a set of those services; a **sandbox** is one running
deployment of it. The `veris` CLI signs in, defines environments, starts
sandboxes, seeds them, and runs the application's own tests through them:
`veris run` reroutes the code's outbound HTTP(S) into a sandbox from outside the
process, so the code under test keeps its production hostnames, credentials and
client stack, and every run ends with a **receipt** of what the sandbox received.

For a CLI-owned workflow, install the CLI once on the controlling machine:

```
curl -LsSf https://raw.githubusercontent.com/veris-ai/veris-cli/main/scripts/install.sh | sh
veris login
```

An OpenCode sandbox plugin can instead own the session and its attached twin.
The same skills then use its remote application tools and current-run evidence;
local CLI installation and Docker are not prerequisites for that session path.
See the OpenCode configuration below.

## veris

Three commands an engineer invokes with a task. The skills keep the same
measurement and evidence gates across CLI-owned and plugin-managed execution.

| command | what it does | not done until |
|---|---|---|
| `setup` | verifies the current session or wires a CLI-owned workflow, identifies vendors, and proves one application run reaches the twin | evidence attributable to that run shows the required vendor calls and expected responses/state |
| `build <issue link \| prompt>` | measures every vendor claim the task rests on against the twin before designing, implements, proves the changed application flow against the twin | every claim measured before the first source edit; a receipt from the changed flow; a PR stating what was verified and what is assumed |
| `fix <issue link \| prompt>` | reproduces the failure the issue describes through the repository's own code before designing, fixes it, proves the same failure closed | the failure reproduced before the first source edit; the same failure re-run green with a receipt; the PR as above |

The reference set lives once in `veris/skills/veris-reference/`. Claude and Codex
ship that canonical tree; the OpenCode npm package bundles it and exposes its
files through `verisSkill`. References are loaded when a command needs them.

### Install

Claude Code:

```
/plugin marketplace add veris-ai/plugins
/plugin install veris@veris
```

Then, in a repository:

```
/veris:setup
/veris:build https://github.com/org/repo/issues/42
/veris:fix   "create_invoice duplicates the invoice when the response is lost"
```

Codex reads the same marketplace:

```
codex plugin marketplace add veris-ai/plugins
codex plugin add veris@veris
```

Codex names plugin commands after the plugin: `$veris:setup`,
`$veris:build <issue link or prompt>`, `$veris:fix <issue link or prompt>`.

For a CLI-owned container workflow, commands use `veris`, Docker and the control
plane from the shell. Codex's default sandbox has neither network nor the Docker socket, so start it with
`codex -s danger-full-access -a never` (or pre-approve `veris` and `docker` prefix
rules). Otherwise every command waits on an approval.

OpenCode uses the Veris skills package plus one selected sandbox plugin
(the renamed skills package needs its first release):

```json
{
  "$schema": "https://opencode.ai/config.json",
  "plugin": [
    "@veris-ai/veris-opencode@latest",
    "@veris-ai/daytona-opencode@latest"
  ]
}
```

For E2B replace the second entry with `@veris-ai/e2b-opencode@latest`. These are
OpenCode plugins configured in `opencode.json`, not `npx` commands. Set the
provider's host credentials and environment, restart OpenCode, then run
`/veris:setup`, `/veris:build` or `/veris:fix`. Setup verifies the attached session
before local CLI/Docker checks; the provider owns its twin and cleanup. Changes
return through `gitSync` to a local `opencode/N` branch; ignored evidence needs an
explicit handoff. Record the resolved published versions for reproducibility.

See [OpenCode installation and release prerequisites](veris/.opencode-plugin/README.md)
and the [provider differences](veris/skills/veris-reference/opencode.md). The
published `@veris-ai/veris-sim-opencode` 0.7.0 release predates this session path.
The next release uses `@veris-ai/veris-opencode`, matching the `veris` name in
Claude and Codex, with `veris/skills` as its canonical content. After that release,
replace the old package entry in your OpenCode config with the new one; install
only one skills package. It can also be installed alone for a CLI-owned workflow.

Any other agent, through the `skills` CLI:

```
npx skills add veris-ai/plugins --all
```

### The sentence in your prompt

A few instructions decide whether a change is proven or only described, and they
carry force in proportion to how close they sit to the task. Measured across
matched runs of one task, the same directive changed the work 3 times out of 3
when it was a line in the prompt, 2 out of 6 from a hook, and 0 out of 4 from
skill prose that was demonstrably read in 4 of those runs. The skills are a good
channel for a procedure and a poor one for an imperative.

So the plugin ships those imperatives outside the skill text. In Claude Code,
installing it installs a `UserPromptSubmit` hook (`veris/hooks/`) that puts four
short lines on each turn: make a named failure happen against the twin before
the design is fixed, drive the default path, claim no red and no green without
the receipt, and give every premise you measured false its own line in the
change description. It is conditional on a twin being in play, and five lines
long, because it rides every prompt of every session. Nothing else in the plugin
depends on it; deleting `veris/hooks/hooks.json` turns it off.

Your own prompt is the stronger channel. Paste this beside the ticket:

```
Before you fix this: make the failure happen against the twin and drive the current code through it; then drive the call this ticket names from a caller you did not change, twice, and count what the twin stored.
```

### The credential

In a plugin-managed OpenCode session, use the provider host variables described
[here](veris/skills/veris-reference/opencode.md#discovery-and-control-access).
The following login applies to CLI-owned workflows.

`veris login` pairs the machine once: it prints a code and a link, you approve in
the studio, and the key is saved under `~/.veris` with owner-only permissions. The
skills never see or print it. In CI, set `VERIS_API_KEY` instead; it beats the
saved profile on every command.

### Hosted execution

The hosted tier has provider recipes for
[Daytona](veris/skills/veris-reference/daytona.md) and
[E2B](veris/skills/veris-reference/e2b.md), with selection and evidence rules in
[hosted.md](veris/skills/veris-reference/hosted.md). Both use the provider's
published SDK as shipped — `@veris-ai/daytona`, a drop-in for `@daytona/sdk`,
and `@veris-ai/e2b` — through a task-local script: attach a separate
application-test box to the task's existing twin
(`create({ veris: { attachSandboxId } })`), upload the code, install
dependencies, run commands with the trust environment applied, and read the
receipt since a baseline. Neither package ships a CLI the skills depend on.
Each task resolves `latest` itself and lets `--save-exact` and the lockfile hold
it for that run, so a recorded version describes the evidence instead of
dictating the next run; `tests/skill_version_claims.sh` fails a skill document
that pins a specifier, records what `latest` resolved to, or names the removed
`veris-daytona` executable. A Daytona box running a Node application needs Node
24 or newer in the image: the SDK's proxy routing rests on `NODE_USE_ENV_PROXY`
and an `Agent` `proxyEnv` that Node 20 ignores, so there the canary and `curl`
still pass while every Node client fails DNS. The Daytona recipe spells out what the SDK sets for the
proxy and for trust, and what a Node process needs on top; provider-specific
setup and limits are in each recipe. OpenCode provider configuration and
session-owned sandboxes are a separate workflow.

### Versions

These entries describe the source plugin history. The old
`@veris-ai/veris-sim-opencode` npm 0.7.0 tarball predates the CLI migration below;
matching version numbers across that old distribution and this source do not
establish matching content.

Every release changes what the commands do, so a report of a run names the
version it ran, and a series of runs meant to be compared with each other pins
one version for all of them. The 0.5.0–0.6.6 entries below were reconstructed
from the commits and are dated by them, not by a release note written at the
time.

0.8.0 — the reconciliation. After the green run and before the PR, each measured
fact the change claims to encode gets a **falsifier** — the input or state under
which the shipped code would violate it — driven through the shipping path under
`veris run` and read back off the twin; a reproduction is a contradiction, and
the code changes. `ledger.sh` fails an `ENCODED` row without that falsifier and
the `run_ref` of the run that drove it, requires a `DEFAULT_PATH` row (the call
the task names, from a caller that changed nothing, driven twice, rows counted),
refuses `--against-diff` without the `record.json` that pinned the base and no
longer takes `--base`, stamps each row through a new `ledger.sh add`, and rejects
a ledger whose rows all share one timestamp. `setup` stops gitignoring
`.veris/tasks/`. The proportional path's single end-to-end run becomes a
deliverable with a pasted receipt, and an unreachable sandbox stops the task
instead of hiding in it. `fix` writes a differential before its first twin call
and re-asks after the code survey whether the code alone explains the symptom;
the manual is documented as a list of transport-visible faults in its author's
order, not a ranked catalogue of the repository's defects. A `UserPromptSubmit`
hook ships in `veris/hooks/`, because a directive in skill prose does not move
work that the same words in the prompt do.

0.7.4 (unreleased) — the Daytona recipe is written around the `@veris-ai/daytona`
SDK as shipped (0.3.1 and later): the run is a sequence of SDK calls the
agent's own task-local script makes (attach to the task's twin, upload, install,
patch bundled CAs, baseline, run with the trust environment, receipt, delete),
with the SDK's README and typings as the reference rather than a reprinted script. It states what the SDK sets
for egress and trust and what a Node process needs beyond it: `NODE_USE_ENV_PROXY`,
`--use-openssl-ca`, and the Agent proxy preload for SDKs that build their own
`https.Agent` (stripe-node measured). Also: one organisation for the CLI and the SDK, `COPYFILE_DISABLE`
on macOS uploads, workspace packages staged as a copy, and the application's own
database inside the box until data planes are carried through. Run against a live
box on 2026-09-08 (Medusa's payment module through the Stripe provider).

0.7.3 (unreleased) — OpenCode commands load skills from the installed package in
Daytona and E2B sessions, reuse the attached twin, and require evidence attributable to each
application run. The plugin owns lifecycle; generated changes use its git sync.

0.7.2 — a hosted tier, with a Daytona provider recipe. `setup` can run tests remotely
when requested, or when the code needs redirection and Docker is unavailable.
`veris-reference/hosted.md` describes selection, remote workload preparation, trace
evidence, project notes and cleanup; `veris-reference/daytona.md` holds the commands
and provider limits. The flow is `veris up`, then `provision`, `push`, `exec` and
`teardown` through `veris-daytona`, with the twin's trace as the receipt. `build` and
`fix` reuse the recorded commands. The runner uses an exact published version through
`npx`; setup checks that release contains all four CLI verbs before creating resources.
Earlier Node/Stripe and Python/Stripe trials informed the guidance; these
documentation changes were not run against a live box.

0.7.1 — the skills adapters retired their MCP registration, alongside the
first-run lessons of two measured sessions. At that release they registered
commands only: `.mcp.json`, `.codex-mcp.json` and the OpenCode plugin's
injected server are gone, since every mechanism is a `veris` command and a machine
signed in with `veris login` has no `VERIS_API_KEY` for them to send. `record.sh` runs
the command after `--` as argv, never through `sh -c`, and treats a command that cannot
start as an error rather than a verdict; `ledger.sh` requires state read back on a
`REPOSITORY` row and refuses one that cites a stub. `setup` adopts only an environment
that is the project's, reads the twin's published key instead of inventing one, fixes
the image rather than the run line, and recognises the two `doctor` lines that mean
the agent is in a sandbox of its own.

0.7.0 — CLI-first. Most mechanisms formerly spelled out as HTTP calls, MCP tools
and shell scripts moved to `veris` commands: `login`, `doctor`, `services`,
`env create`, `up`, `sandbox data add|schema|get`, `sandbox services manual`,
`sandbox trace`, `sandbox clock`, `run`, `snapshot`, `baseline`, `down`. The skills
keep the gates and the judgment, in plain language: measure before designing,
reproduce before fixing, prove with a receipt. `preflight.sh` and `.veris/run.sh`
were retired; CLI environment configuration lives in `.veris/twin.yaml`, written by `veris env create`. Current setup also
writes `.veris/setup.json` for source/build facts and artifact policy, and keeps
the direct-tier reference. The container tier with
`--patch-bundled-cas` is the default for code under test.

0.6.9 — the clock is sandbox state, not a service choice.

0.6.8 — the coverage catalogue is the first door, not the last.

0.6.7 — the word *world* is gone: `veris-reference/worlds.md` is `state.md`.

0.6.6 — the proof scripts and the measurements-against-the-diff gate. `record.sh`
pins the declared source before the failing run, refuses a red whose source or
build output has moved since, and writes down what each run did; `ledger.sh`
types every measurement, requires evidence that survives the sandbox, and checks
each encoded row against the diff. `setup` stages both into `.veris/bin/`. The
proportional path gains its floor: a task that drove nothing through the twin has
left the change unproven. Cut as 0.6.6 because 0.6.5 had already shipped as a
docs release while this work carried 0.6.5-rc.1.

0.6.5 — files: bytes go in through the twin's upload route, rows first, files second;
`setup` gains the files step.

0.6.4 — the manual is not a coverage catalogue; discovery runs cheapest-first.

0.6.3 — any identity, however the code got it. Gate 2 had bound only on a key the
change computes, so a change that copies an id — one input reused, another
silently discarded — read the clause, correctly read it as not applying, and
shipped an identity that merges two distinct records. It now binds on any
identity, dedup key or external reference sent across the vendor boundary, and
asks for the general experiment: vary each component independently, omit one,
confirm the vendor stored distinct records. Gate 3 gains sibling branches — the
same response handled inline, selected by a mode or type switch, which a grep for
the changed symbol cannot find — each named and either driven or listed under
limitations. The operations list is named as the one surface that enumerates
operations.

0.6.2 — a derived identity is proven, not looked up. Gate 2 had presupposed that
the change copies an identity the vendor owns; a key the change computes — parts
joined, a value normalized, truncated, hashed — has no row to read, so the gate
cleared the source fields and let the collision through in the derivation. It now
asks for two inputs the code must keep apart that map to the same key, both driven
through the same path, the vendor's rows counted. Gate 3 gains the entry points
that reach the changed lines and which of them the green run drove; the rest go
under limitations and risks.

0.6.1 — OpenCode install, with the API base defaulted inline; one plugin file
registers the commands.

0.6.0 — gate ordering is the evidence. The red run happens against unmodified
code before the first edit, and a red produced later by stashing the fix proves
nothing. Proportionality to the vendor boundary: a change with no vendor claim on
its path is verified the repository's own way and spends the twin on one
end-to-end run. Bulk reconnaissance is delegated rather than read into the
conversation.

0.5.0 — diagnose from the code first. Every distinct defect that could produce the
symptom is listed from code evidence, the repository's own defects included,
before any sandbox: the twin confirms a diagnosis, it does not choose one. With
it: the coverage contract, escalation when a task's premise measures false, suite
discipline, and the `.veris/NOTES.md` setup handoff.

0.4.3 — `build` and `fix` seed the world before they measure.

0.4.2 — Codex fixes measured in a clean box.

0.4.1 — `test` removed.

0.4.0 — `setup --direct`: a direct-connection tier for applications whose config
reads each service base URL from its `env_hint` variable.

0.3.0 — `test`: run one named test through the proxy with a per-test verdict.

0.2.1 — `setup` names the services it inferred when asking to create an environment.

0.2.0 — three commands (`setup`, `build`, `fix`) replace the 0.1 skills.
