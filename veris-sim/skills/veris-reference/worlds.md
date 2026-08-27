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
- A column holding a file's bytes reads back as a placeholder string naming
  the vendor download instead of the bytes; size and checksum columns return
  in full. The bytes are still seedable, stored, and downloadable through the
  vendor's own API.

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
  the run ends. Promotion copies the world into the environment's default;
  every later `create_sandbox`, including the proxy's per-run ones, starts
  from it. The capture is a boundary — the sandbox is left frozen and
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
