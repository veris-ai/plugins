# Sandbox state: seeding rows, loading files, isolation, reset, keeping a world

## One sandbox per task

`veris up` makes it; `veris down` deletes it; its TTL is the backstop. A sandbox is
hermetic: two sandboxes never share rows, faults, the clock or a callback
registration. Ending the task is the teardown. A sandbox left behind by an
interrupted session is still alive, and a later session could mistake it for its own.
`veris sandbox list` shows the in-use environment's sandboxes, and
`veris sandbox list --all` shows every environment's.
`veris sandbox delete --id <id> --yes` removes one that is not this folder's, and
`veris down --all --yes` deletes every sandbox of the in-use environment.

## Seeding rows

- `veris sandbox data get <twin>` lists every table with its row count. The cheapest
  way to see what a twin holds before reading any shape.
- Ids come from `veris sandbox data get <twin> <table>`, never guessed and never
  copied from another sandbox. Use a vendor test value or a named profile only when
  the manual names it.
- Add exact rows in the shapes `veris sandbox data schema <twin> --table <t>` names,
  from a JSON file keyed by twin name; one file can cover several twins:
  ```
  veris sandbox data add rows.json
  ```
  ```json
  {"stripe": {"customers": [{"id": "cus_test_ada", "email": "ada@example.com", "created": 1756900000}]},
   "postgres": {"sql": "data/schema.sql"}}
  ```
  Adding is additive. The command prints the twin's own added counts and the
  state-version change. When a row is refused it prints the twin's reasons line by
  line and stops, with nothing applied for that twin; a missing required column is
  the usual reason. Fix the file and add it again. A postgres twin takes SQL under
  its key, with the path relative to the project directory. Rows added this way die
  with the sandbox; keep them with `veris snapshot create` or `veris baseline
  promote` (below).
- Changing or removing a row that already exists is by its key, one row at a time:
  ```
  veris sandbox data set stripe customers id=cus_test_ada name=Ada
  veris sandbox data delete stripe faults id=flt_1 --yes
  ```
  The key goes among the fields, and `set` leaves the columns you did not name alone.
  Each value is read as JSON and kept as the literal string when it is not one: `id=1`
  is a number, `enabled=true` a boolean, `mode=permissive` a string. `delete` asks
  first, since a row does not come back; `--yes` answers, and off a terminal it refuses
  without one. A row the twin booted with changes the same way, a setting row included.
- A twin refuses to delete its singleton rows: the clock, the client registration, the
  auth mode and the delivery log. It says what to do instead; change those rows with
  `veris sandbox data set`.
- A clean slate for one twin between probes, leaving the others and the clock alone.
  There is no verb for this, so it is a curl at the twin's control URL, which
  `veris sandbox services get <twin>` prints:
  ```
  curl --fail-with-body -sS -X POST "<control url>/veris/reset" -H 'Content-Type: application/json' -d '{"profile":"default"}'
  ```
  `{"profile": …}` loads the packaged starting data, and `{"data": {…}}` loads exact
  rows. Neither may leave an empty dataset. Any other key is refused with 422, and the
  data is left as it was. This works on an image-booted sandbox too.
- File bytes are not rows. See **Files**.

## Files

A file hangs off a row: a Drive file belongs to a user, a Dropbox file to an account,
an attachment to an issue. So the order is fixed: rows first, files second.

Twins take files in two ways, and the manual says which way a twin takes them. A twin
whose files sit in a tree takes them through its own upload route. A twin whose files
are attachments takes bytes only through the vendor's own upload API, the way the app
sends them. Uploading to a twin of the second kind answers 404, "this service does not
support folder imports". That is a plain refusal, and it is evidence, not noise.

1. `veris sandbox services manual <twin>` names the table that owns files;
   `veris sandbox data schema <twin> --table <t>` shows its shape.
2. Seed the rows the files need, an owner, a folder, a repository, with
   `veris sandbox data add`, or pick an owner already in the sandbox from
   `veris sandbox data get <twin> <table>`.
3. Post the bytes to the twin's control URL with that owner's id. One file:
   ```
   curl --fail-with-body -sS -X POST --data-binary @report.pdf \
     "<control url>/veris/files?path=Inbox/report.pdf&owner=<owner id>"
   ```
   A whole tree, as a zip:
   ```
   curl --fail-with-body -sS -X POST --data-binary @fixtures.zip \
     "<control url>/veris/files?prefix=Client%20Uploads&owner=<owner id>"
   ```
   `mode=merge` (default) replaces matching paths and keeps the rest; `mode=replace`
   needs a `prefix` and makes that subtree exactly the upload. Leave `owner` out and
   the manual's default identity owns the files. The reply lists what was created.
4. Read back with `veris sandbox data get <twin> <files table>`. A file's content
   column shows the SHA-256 of its bytes; compare with `shasum -a 256` of the local
   file. The vendor's own download endpoint returns the exact bytes.

Limits: 1 GB per file, 20 GB and 25,000 files per environment. An upload over a limit
is refused with the number; nothing is truncated.

Files follow rows. A reset restores the seeded set. A promote or a snapshot keeps the
files. Files the app uploaded during a run go away with the sandbox, unless the state
is kept.

A sandbox whose baseline holds many files stays provisioning for a few minutes while
they are copied in. `veris up` waits five minutes by default; give it more with
`--timeout 10m`. Only `failed` is a failure, and `veris up` exits 1 on it with the
reason. A timeout exits 4 and keeps the sandbox for `veris status` to pick up. A data
file the twin refuses during `veris up` exits 1 with the sandbox kept.

Rows-only state is cheap to seed per task and does not need to be kept.

## Isolation inside one sandbox

Give each test its own root resource and clean up shared controls: the clock,
unscoped faults, reused OAuth connections and the callback URL are shared by every
test in a sandbox.

## Reset

`veris sandbox reset` restores every twin and the shared clock atomically; if one
twin fails, existing state stays. Do not send traffic during a reset. A reset empties
the request log (ids keep counting), so save `veris sandbox trace` first if you need
it. A sandbox booted from a snapshot or a promoted baseline cannot be reset: reseeding
would replace what the image pinned, and the CLI says the fresh copy is
`veris down && veris up`. One row of such a sandbox still changes with
`veris sandbox data set`; only the whole-sandbox reset is refused. The per-twin reset
above works either way.

## Keeping the state a session built

The rows worth keeping usually exist only at the end of a live session. Two ways to
keep them, chosen by who should start from them:

- **Every future sandbox of this environment:** `veris baseline promote`. It copies
  the sandbox's state, files included, into the environment's default; every later
  `veris up`, including the fresh sandbox a `veris run --fresh` makes, starts from it.
  The capture is a boundary: the source sandbox is left frozen and scrubbed, then
  deleted. `--keep-source` keeps it instead. Either way, promote is the last thing done
  with that sandbox. Done when `veris baseline get` shows the pin. Only `setup`
  promotes, and only with the engineer's yes.
- **Only some runs**, an empty account and a populated one, a trial and an expired
  trial: `veris snapshot create --name <name>`. Many per environment; the default
  boot is unchanged. Names are not unique; the newest wins a name lookup, so
  `veris snapshot list` and quote the id. The source sandbox is left frozen and
  scrubbed for you to delete (`--delete-source` does it at once).
  `veris up --boot snapshot --snapshot <name>` boots one (`--snapshot` alone is
  refused), and an explicit snapshot beats the environment's baseline.
  `veris baseline set <snapshot>` makes one the default later; `veris baseline clear`
  returns to the packaged data. A snapshot cannot be deleted while a sandbox booted
  from it is alive; the delete answers 409 until that sandbox is gone.

Both captures block on the control plane. After about 150 s the answer may be dropped
while the capture itself continues. The CLI then polls for the new row or the changed
pin, rather than sending the capture again, which would mint a second image. Do not
re-run it yourself. `--clock-restore today|frozen|rebase` on either says what a
sandbox booted from the capture does with its clock (default `today`).

Check the state reads back the way the tests expect before keeping it; every later
boot inherits it.
