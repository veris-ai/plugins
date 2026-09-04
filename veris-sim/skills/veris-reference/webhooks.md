# Receiving callbacks and webhooks

The proxy routes your code out; a webhook comes back in, and a sandbox in the cloud
cannot reach an application on a laptop or a private network. Localhost and private
addresses are not delivery targets.

**Under `veris run`:** `--expose <port>` (the port your app listens on) opens a public
tunnel and registers it with the sandbox; `proxy.expose` in `.veris/twin.yaml` sets
it for every run. The tunnel is cloudflared, and `veris doctor` says whether it is on
PATH. The app shares the proxy's port space, and 8081 and 8443 are the proxy's own
listeners, so have the app listen elsewhere, 3000 say. Your app is handed
`VERIS_PUBLIC_URL` and registers it with the vendor through the vendor's own API,
because that registration call is also code under test.
`--require-callback <path>[:n]` (or `'*'` for any path; `proxy.require_callback` in
`.veris/twin.yaml` sets the default) asserts delivery the way `--require-service`
asserts egress: a webhook suite that received nothing must not pass. The run prints
what arrived as `the sandbox delivered N callback(s):` lines, one per path with its
status. A sandbox per run (`--fresh`) keeps concurrent runs from overwriting each
other's callback URL.

**Without the proxy:** give the sandbox a public HTTPS address at creation,
`veris up --callback-url <url>` (or `callback_url` in `.veris/twin.yaml`). Expose a
local receiver with `cloudflared tunnel --url http://localhost:8000` and use that URL
both as the app's callback URL and as the sandbox's; if the app refuses loopback or
private addresses, expose the twin's URL through the same tunnel too.

The manual names any signing secret or twin-specific setup. Signatures are shown,
never verified by Veris: verifying them is the app's job, and the secrets live in the
twin's rows. `veris doctor` reports the sandbox's callback registration and probe
state: `Callbacks registered at <url> (probe answered)` is good; `the tunnel behind
it is gone` means an earlier run left the registration. Confirm the last probe result
came from the application, not a tunnel error page. Without inbound HTTP, read
`deliveries` and `delivery_attempts` through
`veris sandbox data get <twin> deliveries`, and `veris sandbox trace --tier delivery`
for the delivery exchanges; add `delivery_rules` rows with `veris sandbox data add`
before the triggering action to suppress or delay delivery. A delivery the sandbox
refused to send, because the destination was private or plain HTTP, shows in
`delivery_attempts` with the reason. A frozen sandbox clock pauses delivery;
`veris sandbox clock set --live` resumes it.
