# opencode-veris

[Veris](https://veris.ai) for [OpenCode](https://opencode.ai): three
engineer-invoked commands. Veris runs stateful
twins of the external services an application calls; `veris run` reroutes
the application's outbound HTTP(S) into a sandbox from outside the process,
so the code under test keeps its production hostnames, credentials and
client stack, and ends each run with a receipt of what the sandbox received.

## Install

```
opencode plugin opencode-veris -g
```

(or add `"opencode-veris"` to the `plugin` array in
`~/.config/opencode/opencode.json`), then restart opencode. The commands run
the `veris` CLI: install it once with the line in the repository README and
sign in with `veris login`. `/veris:setup` checks both and says what is
missing. The plugin reads no credential and registers no server of its own.

## Commands

| command | what it does |
|---|---|
| `/veris:setup` | wires the repository to a Veris environment, once — credential, environment, transport, one smoke run with proof of arrival |
| `/veris:build <issue link \| prompt>` | measures every vendor claim the task rests on against the twin before designing, proves the change through `veris run` with a receipt |
| `/veris:fix <issue link \| prompt>` | reproduces the failure the issue describes before designing, proves the same failure closed with a receipt |

The commands are plain OpenCode commands: only the engineer can start them,
the model cannot invoke them on its own.

For application tests on a separately managed hosted box, setup reads the bundled
`skills/veris-reference/hosted.md` and its `daytona.md` or `e2b.md` provider recipe.
E2B uses an exact published SDK version and attaches to the task's existing
twin. These recipes do not configure an OpenCode provider plugin or manage a
session-owned sandbox.

Source and the shared skill files: https://github.com/veris-ai/plugins
