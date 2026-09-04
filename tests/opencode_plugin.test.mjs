import assert from 'node:assert/strict'
import { test } from 'node:test'
import { createHash } from 'node:crypto'
import { execFileSync } from 'node:child_process'
import { cpSync, existsSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, rmSync, symlinkSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { dirname, join, posix, resolve } from 'node:path'
import { fileURLToPath, pathToFileURL } from 'node:url'
import plugin from '../veris/.opencode-plugin/index.js'

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..')
const pkg = join(root, 'veris/.opencode-plugin')
const skills = join(root, 'veris/skills')
const ctx = { sessionID: 'session-current' }
const read = async (hooks, path) => JSON.parse(await hooks.tool.verisSkill.execute({ path }, ctx))
const files = (dir, prefix = '') => readdirSync(dir, { withFileTypes: true }).flatMap((e) =>
  e.isDirectory() ? files(join(dir, e.name), `${prefix}${e.name}/`) : [`${prefix}${e.name}`])

// Models each provider's public composition boundary. Real released hooks and
// receipt renderers are additionally exercised by opencode_providers.mjs.
for (const provider of ['daytona', 'e2b']) {
  for (const order of ['skills-first', 'provider-first']) {
    test(`${provider}: commands and assets survive remote file replacements (${order})`, async () => {
      const hooks = await plugin()
      const remote = { tool: Object.fromEntries(['bash', 'read', 'write', 'edit', 'multiedit', 'ls', 'glob', 'grep', 'gitSync', 'verisReceipt'].map((name) =>
        [name, { execute() { throw new Error('No host files exist in remote repository') } }])) }
      if (provider === 'daytona') remote.tool.verisTwin = { execute() {} }
      const composed = Object.assign({}, ...(order === 'skills-first' ? [hooks.tool, remote.tool] : [remote.tool, hooks.tool]))
      const cfg = { plugin: [`@veris-ai/veris-sim-opencode@latest`, `@veris-ai/${provider}-opencode@latest`] }
      await hooks.config(cfg)
      assert.deepEqual(Object.keys(cfg.command).sort(), ['veris:build', 'veris:fix', 'veris:setup'])
      assert.equal(cfg.mcp, undefined)
      assert.equal(cfg.permission, undefined)
      assert.equal(composed.read, remote.tool.read)
      for (const name of ['setup', 'build', 'fix']) {
        const template = cfg.command[`veris:${name}`].template
        assert.equal(template.split('$ARGUMENTS').length, 2)
        assert.doesNotMatch(template, /!`|(?:^|\s)@|\/Users\/|\/tmp\//)
        const path = template.match(/path "([^"]+)"/)[1]
        const result = JSON.parse(await composed.verisSkill.execute({ path }, ctx))
        assert.equal(result.content, readFileSync(join(skills, path), 'utf8'))
        assert.equal(result.session_id, ctx.sessionID)
      }
    })
  }
}

test('configuration preserves user commands, MCP, skills and both permission shapes', async () => {
  const hooks = await plugin()
  for (const permission of ['deny', { '*': 'ask', veris_reset_sandbox: 'deny' }]) {
    const cfg = {
      plugin: ['@veris-ai/e2b-opencode@latest'],
      command: { 'veris:setup': { template: 'user override' }, custom: { template: 'custom' } },
      mcp: { veris: { type: 'remote', url: 'https://custom.invalid/mcp', oauth: false } },
      skills: { paths: ['/user/skills'] }, permission,
    }
    const before = structuredClone(cfg)
    await hooks.config(cfg)
    await hooks.config(cfg)
    for (const key of ['plugin', 'mcp', 'skills', 'permission']) assert.deepEqual(cfg[key], before[key])
    assert.deepEqual(cfg.command['veris:setup'], before.command['veris:setup'])
    assert.deepEqual(cfg.command.custom, before.command.custom)
    assert.equal(Object.keys(cfg.command).length, 4)
  }
})

test('all canonical references resolve through the tool and script bytes survive remote staging', async () => {
  const hooks = await plugin()
  const dest = mkdtempSync(join(tmpdir(), 'veris-remote-stage-'))
  try {
    for (const path of files(skills).filter((p) => /\.(md|sh)$/.test(p))) {
      const result = await read(hooks, path)
      assert.equal(result.content, readFileSync(join(skills, path), 'utf8'))
      assert.equal(result.sha256, createHash('sha256').update(result.content).digest('hex'))
      for (const match of result.content.matchAll(/\[[^\]]*\]\(([^)]+)\)/g)) {
        const target = match[1].split('#')[0]
        if (!target || /^(?:[a-z]+:|\/)/i.test(target)) continue
        const linked = posix.normalize(posix.join(posix.dirname(path), target))
        assert.ok((await read(hooks, linked)).content, `${path} -> ${linked}`)
      }
      if (path.endsWith('.sh')) {
        const staged = join(dest, posix.basename(path))
        writeFileSync(staged, result.content)
        assert.equal(createHash('sha256').update(readFileSync(staged)).digest('hex'), result.sha256)
        execFileSync('sh', ['-n', staged])
      }
    }
  } finally { rmSync(dest, { recursive: true, force: true }) }
})

test('resource tool rejects traversal, absolute files and unknown resources', async () => {
  const hooks = await plugin()
  for (const path of ['/etc/passwd', '../package.json', 'setup/../../secret.md', 'setup/../fix/SKILL.md', 'setup//SKILL.md', 'setup/%2e%2e/secret.md', 'veris-reference/missing.md']) {
    await assert.rejects(() => read(hooks, path))
  }
})

test('packed public entrypoint loads with canonical content, no source checkout or remote reads', async () => {
  const dir = mkdtempSync(join(tmpdir(), 'veris-package-'))
  try {
    const stage = join(dir, 'veris/.opencode-plugin')
    mkdirSync(stage, { recursive: true })
    for (const file of ['package.json', 'index.js', 'README.md']) cpSync(join(pkg, file), join(stage, file))
    cpSync(skills, join(dir, 'veris/skills'), { recursive: true })
    const tarball = process.env.VERIS_TEST_TARBALL || join(stage,
      JSON.parse(execFileSync('npm', ['pack', '--json', '--cache', join(dir, 'npm-cache')],
        { cwd: stage, encoding: 'utf8' }))[0].filename)
    const install = join(dir, 'install/node_modules/@veris-ai/veris-sim-opencode')
    mkdirSync(install, { recursive: true })
    execFileSync('tar', ['-xzf', resolve(tarball), '--strip-components=1', '-C', install])
    symlinkSync(join(pkg, 'node_modules/zod'), join(dir, 'install/node_modules/zod'))
    const manifest = JSON.parse(readFileSync(join(install, 'package.json'), 'utf8'))
    assert.equal(manifest.name, '@veris-ai/veris-sim-opencode')
    assert.equal(manifest.version, JSON.parse(readFileSync(join(pkg, 'package.json'), 'utf8')).version)
    assert.equal(manifest.exports['.'], './index.js')
    assert.equal(manifest.publishConfig.access, 'public')
    // Use Node's actual package export resolution from an isolated consumer.
    writeFileSync(join(dir, 'install/load.mjs'), `export { default } from '@veris-ai/veris-sim-opencode'`)
    const { default: packedPlugin } = await import(pathToFileURL(join(dir, 'install/load.mjs')))
    const hooks = await packedPlugin()
    for (const path of files(skills)) {
      assert.deepEqual(readFileSync(join(install, 'skills', path)), readFileSync(join(skills, path)))
      if (/\.(md|sh)$/.test(path)) assert.equal((await read(hooks, path)).content, readFileSync(join(skills, path), 'utf8'))
    }
    // A symlink cannot make the package reader a general host read tool.
    writeFileSync(join(dir, 'outside.md'), 'outside')
    symlinkSync(join(dir, 'outside.md'), join(install, 'skills/setup/outside.md'))
    await assert.rejects(() => read(hooks, 'setup/outside.md'), /outside the skills package/)
    // A damaged installed bundle must not fall back to the source tree.
    rmSync(join(install, 'skills/fix/SKILL.md'))
    await assert.rejects(() => read(hooks, 'fix/SKILL.md'))
    const cfg = {}
    await hooks.config(cfg)
    assert.match(cfg.command['veris:fix'].description, /broken install/)
    assert.match(cfg.command['veris:fix'].template, /loading error and stop/)
    assert.ok(!existsSync(join(install, 'skills/skills')))
  } finally { rmSync(dir, { recursive: true, force: true }) }
})
