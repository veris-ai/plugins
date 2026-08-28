---
name: veris-reference
description: Knowledge the veris-sim commands read on demand - the twin's control surface, fault rows, the proxy run, worlds, webhooks, trust, troubleshooting, the PR evidence shape. Not a command; setup, build and fix name the file to read.
user-invocable: false
disable-model-invocation: true
---

Not a command. `setup`, `build` and `fix` link to the file a step needs:

| file | read it when |
|---|---|
| `twin.md` | a design rests on a claim about the vendor, or you need to see what the vendor did — manual, schema, data, requests, sandbox lifecycle |
| `faults.md` | the task is about a failure, or a case needs a condition the vendor will not produce on demand — fault rows (paths, templates, GraphQL selectors), credentials, the clock |
| `proxy.md` | exercising the change through `veris-proxy` — flags, receipt, what a green proves |
| `evidence.md` | writing the PR's verification section |
| `worlds.md` | the world a sandbox holds: seeding rows, loading files, isolation, reset, promote, snapshots |
| `webhooks.md` | the application receives callbacks |
| `trust.md` | an SDK refuses the proxy's certificate |
| `troubleshooting.md` | what the receipt, an exit code and a vendor-shaped error each mean — which trace tier holds which evidence, and which refusals settle a coverage question |
