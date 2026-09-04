---
name: veris-reference
description: Knowledge the veris-sim commands read on demand - asking the twin, seeding and keeping state, faults and the clock, webhooks, troubleshooting, the PR evidence shape. Not a command; setup, build and fix name the file to read.
user-invocable: false
disable-model-invocation: true
---

Not a command. `setup`, `build` and `fix` link to the file a step needs:

| file | read it when |
|---|---|
| `twin.md` | a design rests on a claim about the vendor, or you need to see what the vendor did: manual, schema, operations, data, trace |
| `state.md` | seeding rows and files, isolation inside a sandbox, reset, snapshots and the baseline |
| `run.md` | exercising the change with `veris run`: the two tiers, the image, what the run hands the workload, the flags that change the verdict, exit codes, what a green proves |
| `direct.md` | the app reads every vendor base URL from the environment and needs no proxy |
| `faults.md` | the task is about a failure, or a case needs a condition the vendor will not produce on demand: fault rows, credentials, the clock |
| `webhooks.md` | the application receives callbacks |
| `troubleshooting.md` | what the receipt, an exit code, a trace tier, a certificate error or a vendor-shaped error means |
| `evidence.md` | writing the PR's verification section |
| `proof.md` | what closes a claim: the three layers, the ledger's four dispositions, the identity a fix rests on |

Every mechanism is a `veris` command, and `veris <command> --help` documents its
flags. A few things have no verb of their own: file upload, changing or deleting rows,
a per-twin reset, the auth mode, the operations list. Each of those is a `curl` to the
twin's control URL, which `veris sandbox services get <twin>` prints, and the file
that covers it shows the call.
`scripts/` holds `record.sh` and `ledger.sh`, the measurement ledger `fix` uses;
`setup` step 9 copies them into the repository's `.veris/bin/`.
