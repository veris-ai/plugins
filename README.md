# Veris plugins

Veris runs stateful twins of the external services an application calls. An
**environment** names a set of those services; a **sandbox** is one running
deployment of it; `veris-proxy` reroutes the application's outbound HTTP(S)
into a sandbox from outside the process, so the code under test keeps its
production hostnames, credentials and client stack, and ends each run with a
**receipt** of what the sandbox received.

## veris-sim

Three commands an engineer invokes with a task, plus the `veris` MCP server.

| command | what it does | not done until |
|---|---|---|
| `setup` | wires the repository to an environment, once: credential, environment, transport (proxy+docker, or `--direct` where the app's config carries the base URLs) | a smoke run's receipt — or, direct tier, the twin's trace — names the service |
| `build <issue link \| prompt>` | measures every vendor claim the task rests on against the twin before designing, implements, exercises the change through `veris-proxy` | every claim measured before the first source edit; a receipt from the changed flow; a PR stating what was verified and what is assumed |
| `fix <issue link \| prompt>` | reproduces the failure the issue describes through the repository's own code before designing, fixes it, proves the same failure closed | the failure reproduced before the first source edit; the same failure re-run green with a receipt; the PR as above |

The reference set lives once, in `veris-reference/` — a directory with a
`SKILL.md` nobody can invoke, so both installers copy it — and is read only
when a command names a file. `setup` also carries `scripts/preflight.sh`
and its own `reference/transport.md`. The sandbox API is
called directly — the `veris` MCP tools for lifecycle, `curl` against
`/veris/*` for the rest — with the exact calls in the references.

### Install

Claude Code:

```
/plugin marketplace add veris-ai/plugins
/plugin install veris-sim@veris
```

The plugin registers the `veris` MCP server; it reads `VERIS_API_KEY` from
your environment (`VERIS_API_BASE` defaults to `https://svc.api.veris.ai`).
Then, in a repository:

```
/veris-sim:setup
/veris-sim:build https://github.com/org/repo/issues/42
/veris-sim:fix   "create_invoice duplicates the invoice when the response is lost"
```

Codex: the same directory is a Codex plugin (`veris-sim/.codex-plugin/plugin.json`);
the skills install into `.agents/skills` with the command below, and the MCP
server is configured in `~/.codex/config.toml`:

```toml
[mcp_servers.veris]
url = "https://svc.api.veris.ai/mcp"
env_http_headers = { "X-API-Key" = "VERIS_API_KEY" }
```

Codex mentions skills rather than namespacing them: `$setup`, `$build <issue
link or prompt>`, `$fix <issue link or prompt>`. Everything else is the same
files.

Any of 76+ agents, through the `skills` CLI:

```
npx skills add veris-ai/plugins
```

### The credential

`setup` reads `VERIS_API_KEY` from the environment. If it is not set, it
gives you one command to run in your terminal (`echo 'export
VERIS_API_KEY=<key>' >> ~/.zshrc && source ~/.zshrc`), waits, and confirms
it is set. The skill writes the key nowhere; the MCP server reads the
environment at session start, so restart the agent after setting it.

### Versions

0.4.1 — `test` removed: the suites it would run are mocked, so it reduced to
setup's smoke run; `build` and `fix` write the vendor-reaching test in their gate.

0.4.0 — `setup --direct`: a direct-connection tier for applications whose
config reads each service base URL from its `env_hint` variable — the
shipped path on platforms without docker (Replit, most PaaS). Trust anchor
becomes the twin's request trace instead of the proxy receipt;
`reference/direct.md` carries the contract. `setup` also accepts service
names to seed environment creation.

0.3.0 — `test`: run one named test, or every test that reaches the vendor,
through `veris-proxy`, with a per-test verdict on whether it reached the twin.

0.2.1 — `setup` names the services it inferred when asking to create an
environment; the reply may add or drop names.

0.2.0 — three commands (`setup`, `build`, `fix`) replace the 0.1 skills
(`setting-up-veris`, `discovering-vendor-behavior`, `integration-testing`).
The knowledge those carried is in `veris-reference/`.
