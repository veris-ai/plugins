# Worlds: the state a sandbox holds - seeding, isolation, reset, promote, snapshots

## The sandbox is the proxy's

A sandbox per run is hermetic; two runs never share state, faults, the clock,
or a callback registration. Ending the run is the teardown. An interrupted
session left in the background is a sandbox still alive that a later session
could mistake for its own.

## Seeding the world

- `GET {control_url}/veris/data` with no parameters lists every table and its
  row count — the cheapest way to see what a service holds before reading
  any shape.
- Ids come from `GET {control_url}/veris/data?entity_type=<table>` — never guessed, never copied from another
  sandbox. Use a vendor test value or named profile only when the manual
  names it.
- Seed exact rows in the shapes `/veris/schema` names:
  ```http
  POST {control_url}/veris/data
  {"data":{"<entity>":[{"<primary-key>":"test-owned-id","<field>":"value"}]}}
  ```
  `PATCH` changes rows by primary key; `DELETE` removes them.
- A clean slate between probes: `POST {control_url}/veris/reset` with
  `{"profile":"default"}`.
- File bytes are not rows — see **Files** below.

## Files

A file hangs off a row: a Drive file belongs to a user, a Dropbox file to an
account, a Hub file to a repository, an attachment to an issue. So the order
is fixed — rows first, files second. Services whose files sit in a tree have
`/veris/files`, and the manual shows it; a service whose files are
attachments takes bytes only through its own upload API, the way the
application sends them, and the manual says so.

1. Read the owner table's shape in `/veris/schema`; the manual names which
   table owns files.
2. Seed the rows the files need — the owner, a folder, a repository —
   through `POST {control_url}/veris/data`, or pick an owner that is already
   in the world from `/veris/data`.
3. Post the bytes with that owner's id. One file:
   ```sh
   curl --fail-with-body -sS -X POST --data-binary @report.pdf \
     "$CONTROL_URL/veris/files?path=Inbox/report.pdf&owner=<owner id>"
   ```
   A whole tree, as a zip:
   ```sh
   curl --fail-with-body -sS -X POST --data-binary @fixtures.zip \
     "$CONTROL_URL/veris/files?prefix=Client%20Uploads&owner=<owner id>"
   ```
   `mode=merge` (default) replaces matching paths and keeps the rest;
   `mode=replace` needs a `prefix` and makes that subtree exactly the
   upload. Leave `owner` out and the manual's default identity owns the
   files. The reply lists what was created.
4. Read back: `GET {control_url}/veris/data?entity_type=<files table>`.

Bytes never go through `/veris/data`, on any service. A file's content column shows the
SHA-256 of its bytes, and the vendor's own download endpoint returns the
exact bytes. Limits: 1 GB per file, 20 GB and 25,000 files per environment;
an import over a limit is refused with the number, nothing is truncated.

Files follow rows: a reset restores the seeded set; `promote_sandbox` and a
snapshot keep them; files the application uploaded during a run go away
with the sandbox unless the world is kept.

## Isolation inside one sandbox

Give each test its own root resource and clean up shared controls: the
clock, unscoped faults, reused OAuth connections, and the callback base URL
are shared by every test in a sandbox.

## Reset

`reset_sandbox` at suite boundaries restores every service and the shared
clock atomically; if one service fails, existing state stays. Do not send
traffic during a reset, and save `/veris/requests` first — every reset clears
request history. A sandbox booted from an image — a promoted environment's
baseline or a snapshot — answers `409`: reseeding would replace that world.

`POST {control_url}/veris/reset` resets one service and leaves the shared
clock alone, and it still works on an image-booted sandbox. Send
`{"profile":"default"}` for the packaged starting data or `{"data":{...}}`
for exact rows; neither may leave an empty dataset, and any other key is
refused with `422`, leaving existing data. Or delete the sandbox and create
another.

## Keeping a world a session built

What the tests need is discovered by writing them, so the world worth keeping
usually exists only at the end of a live session. Two ways to keep it, chosen
by who should start from it:

- **Every future run** → `promote_sandbox` with the run's sandbox id, before
  the run ends. Promotion copies the world, files included, into the
  environment's default; every later `create_sandbox`, including the
  proxy's per-run ones, starts from it. The capture is a boundary — the sandbox is left frozen and
  scrubbed — so it is the last thing done with it.
- **Only some runs** — an empty account and a populated one, a trial and an
  expired trial — → a named **snapshot**. Promoting one of them would
  silently change what every other suite starts from.

  ```sh
  curl --fail-with-body -sS -X POST "${VERIS_API_BASE:-https://svc.api.veris.ai}/v1/environments/$VERIS_ENVIRONMENT_ID/snapshots" \
    -H "X-API-Key: $VERIS_API_KEY" -H 'Content-Type: application/json' \
    -d '{"sandbox_id":"'"$SANDBOX_ID"'","name":"expired-trial"}'
  curl --fail-with-body -sS "${VERIS_API_BASE:-https://svc.api.veris.ai}/v1/environments/$VERIS_ENVIRONMENT_ID/snapshots" -H "X-API-Key: $VERIS_API_KEY"
  ```

  Many snapshots per environment; the default boot is unchanged.
  `create_sandbox` takes an optional `snapshot_id`, and an explicit snapshot
  beats the environment's baseline pin. Snapshot management is HTTP-only;
  only the boot side is on MCP. A snapshot cannot be deleted while a sandbox
  booted from it is alive; that delete answers `409` until the sandbox is
  gone.

Verify a world reads back the way the tests expect before keeping it; every
later boot inherits it.
