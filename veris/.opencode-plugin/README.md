# opencode-veris

[Veris](https://veris.ai) for [OpenCode](https://opencode.ai): three
engineer-invoked commands plus the `veris` MCP server. Veris runs stateful
twins of the external services an application calls; `veris-proxy` reroutes
the application's outbound HTTP(S) into a sandbox from outside the process,
so the code under test keeps its production hostnames, credentials and
client stack, and ends each run with a receipt of what the sandbox received.

## Install

```
opencode plugin opencode-veris -g
```

(or add `"opencode-veris"` to the `plugin` array in
`~/.config/opencode/opencode.json`). Then export your credential and restart
opencode:

```
export VERIS_API_KEY=<key>
```

`VERIS_API_BASE` overrides the control plane (defaults to
`https://svc.api.veris.ai`). Until the key is set, `opencode mcp list` shows
the `veris` server as failed; the commands still run and `setup` walks you
through it.

## Commands

| command | what it does |
|---|---|
| `/veris:setup` | wires the repository to a Veris environment, once — credential, environment, transport, one smoke run with proof of arrival |
| `/veris:build <issue link \| prompt>` | measures every vendor claim the task rests on against the twin before designing, proves the change through veris-proxy with a receipt |
| `/veris:fix <issue link \| prompt>` | reproduces the failure the issue describes before designing, proves the same failure closed with a receipt |

The commands are plain OpenCode commands: only the engineer can start them,
the model cannot invoke them on its own.

Source and the shared skill files: https://github.com/veris-ai/plugins
