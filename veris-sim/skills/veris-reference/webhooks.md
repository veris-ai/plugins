# Receiving callbacks and webhooks

The proxy routes your code OUT; a webhook comes back IN, and a sandbox in the
cluster cannot reach an application on a private network. Localhost and private network
addresses are not delivery targets.

**Under `veris-proxy run`:** `--expose <port>` (the port your app listens on)
opens a public tunnel and registers it with the sandbox. The app shares the
proxy's port space, and 8081 and 8443 are the proxy's own listeners; have the
app listen elsewhere (e.g. 3000). Your app is handed `VERIS_PUBLIC_URL` and
registers it with the vendor through the vendor's own API, because that
registration call is also code under test. `--require-callback
<path>[:count]` (or `'*'`) asserts delivery the way `--require-service`
asserts egress — a webhook suite that received nothing must not pass. A
sandbox per run keeps concurrent runs from overwriting each other's callback
URL.

**Without the proxy:** pass a public HTTPS `client_base_url` to
`create_sandbox`, or update `client.default_base_url` through
`PATCH /veris/data`. Expose a local receiver with
`cloudflared tunnel --url http://localhost:8000` and use that URL as the
application's callback URL and as `client_base_url`; if the application
refuses loopback or private addresses, expose the service `url` through the
same tunnel too.

The manual names any signing key or service-specific setup.
`POST {control_url}/veris/client/probe` checks that the receiver answers;
confirm `last_probe_result` came from the application, not a tunnel error
page. Without inbound HTTP, read `deliveries` and `delivery_attempts`
through `/veris/data`; add `delivery_rules` before the triggering action to
suppress or delay delivery.
