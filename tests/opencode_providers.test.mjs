// Optional contract check against unpacked *published* npm releases, without
// credentials or remote resources. Run with Bun (provider JS uses extensionless
// imports): VERIS_PUBLISHED_PACKAGES=/path/to/unpacked bun test this-file.
// Expected folders: daytona/package and e2b/package. Only the SDK type guard is
// stubbed; the providers' receipt renderers and Daytona config hook run unchanged.
import { describe, test, expect, mock } from 'bun:test'
import { resolve } from 'node:path'
import { pathToFileURL } from 'node:url'
import { readFileSync } from 'node:fs'
import plugin from '../veris/.opencode-plugin/index.js'

const artifacts = process.env.VERIS_PUBLISHED_PACKAGES
mock.module('@veris-ai/daytona', () => ({ isVerisSandbox: (s) => Boolean(s.veris && s.verisSandboxId) }))

const suite = artifacts ? describe : describe.skip
suite('published provider contracts (fake sandbox, no live validation)', () => {
  for (const provider of ['daytona', 'e2b']) {
    test(`${provider} receipt binds to tool session and exposes cumulative/truncated traffic`, async () => {
      const base = resolve(artifacts, provider, 'package')
      const manifest = JSON.parse(readFileSync(resolve(base, 'package.json'), 'utf8'))
      expect(manifest.name).toBe(`@veris-ai/${provider}-opencode`)
      const { verisReceiptTool } = await import(pathToFileURL(resolve(base, `.opencode/plugin/${provider}/tools/veris-receipt.js`)).href)
      let entries = []
      let twin = 'twin-current'
      const calls = []
      const manager = {
        async getSandbox(sessionID) {
          calls.push(sessionID)
          return { verisSandboxId: twin, veris: {
            async receipt(service) {
              const entry = { requests: entries.length, entries, raw: { requests: entries } }
              return service ? entry : { services: { stripe: entry }, mode: 'gateway', integrity: 'verified', leaks: ['ech-possible'] }
            },
          } }
        },
      }
      const tool = verisReceiptTool(manager, 'project', '/host/repo', {})
      const ctx = { sessionID: 'current-session', metadata() {} }
      expect(Object.keys(tool.args)).toEqual(['service'])
      const before = await tool.execute({}, ctx)
      expect(before).toContain('twin-current')
      expect(before).toContain('ZERO')
      expect(before).not.toContain('stripe')
      expect(await tool.execute({ service: 'stripe' }, ctx)).toContain("Receipt for 'stripe': ZERO requests")
      entries = [{ method: 'GET', path: '/veris/schema', status: 200 }]
      // Control traffic is NOT filtered by the published renderer.
      expect(await tool.execute({ service: 'stripe' }, ctx)).toContain('1 request(s)')
      entries = Array.from({ length: 60 }, (_, i) => ({ method: 'GET', path: `/v1/objects/${i}`, status: 200 }))
      const full = await tool.execute({}, ctx)
      const service = await tool.execute({ service: 'stripe' }, ctx)
      expect(full.match(/GET \/v1/g)?.length).toBe(20)
      expect(full).toContain('60 request(s)')
      expect(full).toContain('blind spots: ech-possible')
      expect(service.match(/GET \/v1/g)?.length).toBe(50)
      expect(service).not.toContain('twin-current')
      expect(service).toContain('10 more')
      // A bounded server window can rotate while the displayed count plateaus.
      entries = [{ method: 'POST', path: '/v1/current-run', status: 201 }, ...entries.slice(0, 59)]
      const after = await tool.execute({}, ctx)
      expect(after).toContain('60 request(s)')
      expect(after).toContain('POST /v1/current-run -> 201')
      twin = 'replacement-twin'
      expect(await tool.execute({}, ctx)).toContain('replacement-twin')
      expect(calls.every((s) => s === ctx.sessionID)).toBe(true)
      const unattached = verisReceiptTool({ async getSandbox() { return {} } }, 'project', '/host/repo', {})
      expect(await unattached.execute({}, ctx)).toContain('No Veris twin is attached')
    })
  }
  test('real Daytona config composes in either order and preserves user overrides', async () => {
    const { verisConfig } = await import(pathToFileURL(resolve(artifacts, 'daytona/package/.opencode/plugin/daytona/plugins/veris-config.js')).href)
    const skills = await plugin()
    const priorKey = process.env.VERIS_API_KEY
    const priorBase = process.env.VERIS_API_BASE
    process.env.VERIS_API_KEY = 'fixture-only-not-a-key'
    process.env.VERIS_API_BASE = 'https://control.invalid'
    try {
      for (const hooks of [[skills.config, verisConfig], [verisConfig, skills.config]]) {
        const cfg = { permission: { veris_reset_sandbox: 'deny' }, command: { 'veris:setup': { template: 'user' } } }
        for (const config of hooks) await config(cfg)
        expect(cfg.mcp.veris.url).toBe('https://control.invalid/mcp')
        expect(Object.keys(cfg.mcp)).toEqual(['veris'])
        expect(cfg.permission.veris_create_sandbox).toBe('deny')
        expect(cfg.permission.veris_delete_sandbox).toBe('deny')
        expect(cfg.permission.veris_reset_sandbox).toBe('deny')
        expect(cfg.command['veris:setup'].template).toBe('user')
        const scalar = { permission: 'deny', mcp: { veris: { type: 'remote', url: 'https://user.invalid' } } }
        for (const config of hooks) await config(scalar)
        expect(scalar.permission).toBe('deny')
        expect(scalar.mcp.veris.url).toBe('https://user.invalid')
      }
      delete process.env.VERIS_API_KEY
      const cfg = {}
      await verisConfig(cfg)
      await skills.config(cfg)
      expect(cfg.mcp).toBeUndefined()
    } finally {
      if (priorKey === undefined) delete process.env.VERIS_API_KEY
      else process.env.VERIS_API_KEY = priorKey
      if (priorBase === undefined) delete process.env.VERIS_API_BASE
      else process.env.VERIS_API_BASE = priorBase
    }
  })
})
