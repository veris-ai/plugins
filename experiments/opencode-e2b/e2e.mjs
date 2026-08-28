#!/usr/bin/env node
// OpenCode + E2B + Veris — end-to-end harness.
//
// Proves the composition: an OpenCode agent runs inside an E2B sandbox whose
// vendor traffic is answered by a Veris twin, and the Veris receipt shows the
// agent's own tool calls reaching the twin.
//
//   node e2e.mjs              # headless: drive `opencode run` in the sandbox
//   node e2e.mjs --attach     # interactive: prints an `opencode attach` line
//
// Required env:
//   E2B_API_KEY  VERIS_API_KEY  VERIS_ENVIRONMENT_ID
//   ANTHROPIC_API_KEY (or set --model / MODEL to another provider's)
import { Sandbox } from '@veris-ai/e2b'
import { randomBytes } from 'node:crypto'
import { createInterface } from 'node:readline/promises'

const ATTACH = process.argv.includes('--attach')
const MODEL = process.env.MODEL ?? 'anthropic/claude-sonnet-5'
const PORT = 4096

const need = ['E2B_API_KEY', 'VERIS_API_KEY', 'VERIS_ENVIRONMENT_ID']
const missing = need.filter((k) => !process.env[k])
if (missing.length) {
  console.error(`missing env: ${missing.join(', ')}`)
  process.exit(1)
}
// The agent's model provider is reached from inside the sandbox, so its key
// has to travel with the sandbox — it is not something Veris intercepts.
const providerKey = process.env.ANTHROPIC_API_KEY ?? process.env.OPENAI_API_KEY
if (!providerKey) {
  console.error('missing env: ANTHROPIC_API_KEY (or OPENAI_API_KEY)')
  process.exit(1)
}

const password = randomBytes(18).toString('base64url')
const step = (m) => console.log(`\n\x1b[1m▸ ${m}\x1b[0m`)
const run = async (sbx, cmd, opts = {}) => {
  const r = await sbx.commands.run(cmd, { timeoutMs: 300_000, ...opts })
  if (r.exitCode !== 0 && !opts.allowFail) {
    throw new Error(`command failed (${r.exitCode}): ${cmd}\n${r.stderr || r.stdout}`)
  }
  return r
}

step('creating the E2B sandbox (Veris interception on)')
const sbx = await Sandbox.create({
  timeoutMs: 60 * 60_000,
  // Inbound: `opencode attach` and the health probe reach the sandbox by URL.
  // true is E2B's default and it is create-only. It means the sandbox URL is
  // PUBLIC — the generated OPENCODE_SERVER_PASSWORD below is the only thing
  // guarding the agent. `allowPublicTraffic: false` would require an E2B
  // traffic access token on every request, which `opencode attach` has no way
  // to send (it speaks basic auth only). A workspace adapter can, via
  // target().headers — see the report.
  network: { allowPublicTraffic: true },
  envs: {
    OPENCODE_SERVER_PASSWORD: password,
    ...(process.env.ANTHROPIC_API_KEY && { ANTHROPIC_API_KEY: process.env.ANTHROPIC_API_KEY }),
    ...(process.env.OPENAI_API_KEY && { OPENAI_API_KEY: process.env.OPENAI_API_KEY }),
  },
  veris: {
    // 'open' so npm, the model provider and git work with no allowlist upkeep.
    // The cost is two annotated blind spots (QUIC, ECH) in the receipt; swap to
    // 'strict' + allowOut once you know every host this run touches.
    egress: 'open',
  },
})

try {
  console.log(`  e2b ${sbx.sandboxId}\n  twin ${sbx.verisSandboxId}\n  mode ${sbx.verisMode}`)

  step('what the twin answers for')
  const services = await sbx.veris.services()
  for (const s of services) {
    const hosts = (s.routes ?? []).map((r) => r.host).join(', ')
    console.log(`  ${s.name} [${s.status}]${hosts ? ` ← ${hosts}` : ''}`)
  }

  step('installing opencode in the sandbox')
  await run(sbx, 'npm i -g opencode@latest', { timeoutMs: 600_000 })
  const v = await run(sbx, 'opencode --version')
  console.log(`  opencode ${v.stdout.trim()}`)

  step('seeding a repo whose code calls a vendor')
  // Deliberately hardcoded production hostname: the point is that nothing in
  // this repo knows about Veris, and it still reaches the twin.
  await run(sbx, `mkdir -p ~/app && cd ~/app && git init -q . && cat > charge.sh <<'EOF'
#!/bin/sh
# Charges a customer. Production hostname, no base-URL override anywhere.
curl -sS https://api.stripe.com/v1/charges \\
  -u sk_test_veris: \\
  -d amount=2000 -d currency=usd -d source=tok_visa
EOF
chmod +x charge.sh && git add -A && git -c user.email=e2e@veris.ai -c user.name=e2e commit -qm init`)

  step('starting the opencode server')
  // background: true returns a CommandHandle immediately — it does not go
  // through run(), which expects a finished CommandResult.
  await sbx.commands.run(
    `cd ~/app && opencode serve --hostname 0.0.0.0 --port ${PORT} >~/serve.log 2>&1`,
    { background: true },
  )
  const url = `https://${sbx.getHost(PORT)}`
  const auth = 'Basic ' + Buffer.from(`opencode:${password}`).toString('base64')
  let up = false
  for (let i = 0; i < 60; i++) {
    await new Promise((r) => setTimeout(r, 1000))
    try {
      const res = await fetch(`${url}/global/health`, { headers: { authorization: auth } })
      if (res.ok) { up = true; break }
    } catch {}
  }
  if (!up) {
    const log = await run(sbx, 'cat ~/serve.log', { allowFail: true })
    throw new Error(`opencode server never became healthy at ${url}\n${log.stdout}${log.stderr}`)
  }
  console.log(`  healthy at ${url}`)

  if (ATTACH) {
    step('attach from this terminal')
    console.log(`\n  opencode attach ${url} -p ${password}\n`)
    console.log('  Try, in that session:  run ./charge.sh and tell me what Stripe returned')
    const rl = createInterface({ input: process.stdin, output: process.stdout })
    await rl.question('\npress enter here when you are done to print the receipt… ')
    rl.close()
  } else {
    step('driving the agent headlessly')
    const r = await run(
      sbx,
      `cd ~/app && opencode run --model ${MODEL} ` +
        `"Run ./charge.sh and tell me the charge id and status Stripe returned."`,
      { timeoutMs: 600_000, allowFail: true },
    )
    console.log(r.stdout.slice(-2000))
    if (r.exitCode !== 0) console.log(`  (agent exited ${r.exitCode})\n${r.stderr.slice(-1000)}`)
  }

  step('the receipt — did the agent actually reach the twin?')
  // A green agent run that quietly never called Stripe prints the same thing
  // as one that did. This is the only line that tells them apart.
  await sbx.veris.assertTouched('stripe', { method: 'POST', path: '/v1/charges' })
  const receipt = await sbx.veris.receipt('stripe')
  console.log(JSON.stringify(receipt.services, null, 2))
  console.log(`\n  integrity: ${receipt.integrity}`)
  console.log(`  leaks: ${receipt.leaks.length ? receipt.leaks.join(', ') : 'none'}`)
  console.log('\n\x1b[32m✓ the agent ran in E2B and its vendor call landed on the Veris twin\x1b[0m')
} finally {
  step('tearing down (E2B sandbox + Veris twin)')
  await sbx.kill()
}
