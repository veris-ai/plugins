import { existsSync, readFileSync, realpathSync } from "node:fs"
import { createHash } from "node:crypto"
import { basename, dirname, join, relative, sep } from "node:path"
import { fileURLToPath } from "node:url"
import { z } from "zod"

const pkgDir = dirname(fileURLToPath(import.meta.url))
const manifest = JSON.parse(readFileSync(join(pkgDir, "package.json"), "utf8"))
const COMMANDS = ["setup", "build", "fix"]

// An incomplete tarball must fail rather than silently use different content.
// Only a source checkout falls back to the canonical tree next door.
const sourceCheckout = basename(pkgDir) === ".opencode-plugin" &&
  existsSync(join(pkgDir, "..", ".claude-plugin", "plugin.json"))
const skillsDir = !existsSync(join(pkgDir, "skills")) && sourceCheckout
  ? join(pkgDir, "..", "skills")
  : join(pkgDir, "skills")

function resource(path) {
  if (!/^(setup|build|fix|veris-reference)\/[\w./-]+\.(md|sh)$/.test(path) ||
      path.split("/").some((part) => part === ".." || part === "." || !part)) {
    throw new Error("Use a package-relative skill path, such as veris-reference/session.md")
  }
  const root = realpathSync(skillsDir)
  const file = realpathSync(join(root, path))
  const rel = relative(root, file)
  if (rel.startsWith(`..${sep}`) || rel === "..") throw new Error("Resource is outside the skills package")
  return readFileSync(file, "utf8")
}

// OpenCode expands file and shell references in command templates. Keep skill
// Markdown in tool results. This tool reads on the host even when a provider
// replaces read/bash with remote tools.
function template(name) {
  return [
    `The engineer invoked the veris "${name}" command with arguments: $ARGUMENTS`,
    `Call verisSkill with path "${name}/SKILL.md" and follow its content.`,
    "Use verisSkill for linked package references and helper scripts too.",
    "If that tool is unavailable or the package is incomplete, report the loading error and stop.",
  ].join("\n")
}

const VerisPlugin = async () => ({
  config: async (cfg) => {
    cfg.command ??= {}
    for (const name of COMMANDS) {
      let description = `veris ${name}`
      try {
        description = resource(`${name}/SKILL.md`).match(/^description: (.+)$/m)?.[1] ?? description
      } catch {
        description += " (broken install: reinstall the configured skills package and restart OpenCode)"
      }
      cfg.command[`veris:${name}`] ??= { template: template(name), description }
    }
  },
  tool: {
    verisSkill: {
      description: "Read Veris workflow instructions, linked references, or helper scripts from the installed skills package. Paths are relative to its skills/ directory; this is not an application file tool.",
      args: {
        path: z.string().describe("For example setup/SKILL.md, veris-reference/session.md, or veris-reference/scripts/record.sh"),
      },
      async execute({ path }, ctx) {
        const content = resource(path)
        return JSON.stringify({
          package: `${manifest.name}@${manifest.version}`,
          session_id: ctx.sessionID,
          path,
          sha256: createHash("sha256").update(content).digest("hex"),
          loading: "Resolve relative links against the directory of path, normalize them within skills/, and read them with verisSkill. For scripts, copy content verbatim using the current repository's write tool and verify sha256 before execution. No host filesystem path or download is needed. This session_id identifies OpenCode, not the twin; verify the twin with the provider tools.",
          content,
        })
      },
    },
  },
})

export default VerisPlugin
