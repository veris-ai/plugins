#!/usr/bin/env node
// Attach your local OpenCode to a Veris-intercepted E2B sandbox. Nothing else.
//
//   node attach.mjs            fresh sandbox, prints the attach line
//   node attach.mjs <sbx-id>   reattach to one this script made earlier
//
// Required env: E2B_API_KEY, VERIS_API_KEY, VERIS_ENVIRONMENT_ID, ANTHROPIC_API_KEY
import { Sandbox } from '@veris-ai/e2b'
import { randomBytes } from 'node:crypto'
import { createInterface } from 'node:readline/promises'

const PORT = 4096
const existing = process.argv[2]

for (const k of ['E2B_API_KEY', 'VERIS_API_KEY', 'ANTHROPIC_API_KEY']) {
  if (!process.env[k]) { console.error(`missing env: ${k}`); process.exit(1) }
}
if (!existing && !process.env.VERIS_ENVIRONMENT_ID) {
  console.error('missing env: VERIS_ENVIRONMENT_ID'); process.exit(1)
}

// 1 — the sandbox. This one call also provisions the Veris twin, points the
//     sandbox's egress at the Veris gateway, and installs the interception CA.
//     The password is stashed in metadata so a reattach can recover it.
const password = randomBytes(18).toString('base64url')
const sbx = existing
  ? await Sandbox.connect(existing)
  : await Sandbox.create({
      timeoutMs: 60 * 60_000,
      metadata: { serverPassword: password },
      envs: {
        // opencode serve reads this; without it every route is unauthenticated.
        OPENCODE_SERVER_PASSWORD: password,
        // The agent runs IN here, so its provider key has to travel with it.
        ANTHROPIC_API_KEY: process.env.ANTHROPIC_API_KEY,
      },
      // Default is already true. Being explicit because it is create-only and
      // it is what makes the URL reachable from your laptop at all.
      network: { allowPublicTraffic: true },
      // Agents need npm, git and api.anthropic.com. 'strict' would strand them.
      veris: { egress: 'open' },
    })

const pw = existing ? (await sbx.getInfo()).metadata?.serverPassword : password
console.log(`e2b   ${sbx.sandboxId}`)
console.log(`twin  ${sbx.verisSandboxId}  (mode: ${sbx.verisMode})`)

try {
  // 2 — opencode has to exist in there. Slow (~60-90s) because this is a stock
  //     template; a template with opencode baked in makes this instant.
  const has = await sbx.commands.run('command -v opencode', { timeoutMs: 30_000 })
    .then(r => r.exitCode === 0).catch(() => false)
  if (!has) {
    console.log('installing opencode in the sandbox…')
    await sbx.commands.run('npm i -g opencode@latest', { timeoutMs: 600_000 })
  }
  await sbx.commands.run('mkdir -p ~/work && cd ~/work && git init -q . 2>/dev/null || true')

  // 3 — serve on 0.0.0.0, not the 127.0.0.1 default, or nothing outside the
  //     sandbox can reach it. background:true returns a handle immediately.
  const up = await fetch(`https://${sbx.getHost(PORT)}/global/health`, {
    headers: { authorization: 'Basic ' + Buffer.from(`opencode:${pw}`).toString('base64') },
  }).then(r => r.ok).catch(() => false)
  if (!up) {
    await sbx.commands.run(
      `cd ~/work && opencode serve --hostname 0.0.0.0 --port ${PORT} >~/serve.log 2>&1`,
      { background: true },
    )
  }

  // 4 — the URL. E2B maps <port>-<sandboxid>.e2b.app to the port inside.
  const url = `https://${sbx.getHost(PORT)}`
  const auth = 'Basic ' + Buffer.from(`opencode:${pw}`).toString('base64')
  let healthy = false
  for (let i = 0; i < 60; i++) {
    await new Promise(r => setTimeout(r, 1000))
    try { if ((await fetch(`${url}/global/health`, { headers: { authorization: auth } })).ok) { healthy = true; break } } catch {}
  }
  if (!healthy) {
    const log = await sbx.commands.run('cat ~/serve.log', { timeoutMs: 15_000 }).catch(() => null)
    throw new Error(`server never came up at ${url}\n${log?.stdout ?? ''}${log?.stderr ?? ''}`)
  }

  console.log(`\n  opencode attach ${url} -p ${pw}\n`)
  console.log(`  reattach later:  node attach.mjs ${sbx.sandboxId}`)
  console.log(`  receipt:         sbx.veris.receipt()  — see e2e.mjs`)

  const rl = createInterface({ input: process.stdin, output: process.stdout })
  await rl.question('\npress enter to kill the sandbox and its twin… ')
  rl.close()
} finally {
  await sbx.kill()
  console.log('killed.')
}
