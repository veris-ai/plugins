import { existsSync, readFileSync } from "node:fs"
import { dirname, join } from "node:path"
import { fileURLToPath } from "node:url"

const pkgDir = dirname(fileURLToPath(import.meta.url))
const COMMANDS = ["setup", "build", "fix"]

// Published tarball carries skills/ beside this file (prepack copies it in);
// a git checkout has the tree one level up, at veris/skills/.
function findSkillsDir() {
  for (const dir of [join(pkgDir, "skills"), join(pkgDir, "..", "skills")]) {
    if (existsSync(join(dir, "setup", "SKILL.md"))) return dir
  }
  return undefined
}

function skillDescription(file) {
  try {
    const text = readFileSync(file, "utf8")
    const frontmatter = text.match(/^---\r?\n([\s\S]*?)\r?\n---/)
    const line = frontmatter?.[1]
      .split(/\r?\n/)
      .find((l) => l.startsWith("description:"))
    return line?.slice("description:".length).trim() || undefined
  } catch {
    return undefined
  }
}

// Command templates go through opencode's shell/file interpolation, so they
// must contain no backtick-bang or at-sign sequences. $ARGUMENTS appears once.
function template(skillsDir, name) {
  const base = join(skillsDir, name)
  return [
    `The engineer invoked the veris "${name}" command with arguments: $ARGUMENTS`,
    ``,
    `Read the file ${join(base, "SKILL.md")} now and follow it exactly,`,
    `treating the arguments above as its input. Relative paths inside that`,
    `file (reference/..., scripts/...) resolve against ${base}/, and links`,
    `of the form ../veris-reference/... or ../setup/reference/... resolve`,
    `against ${skillsDir}/.`,
  ].join("\n")
}

function brokenTemplate(name) {
  return [
    `The engineer invoked the veris "${name}" command with arguments: $ARGUMENTS`,
    ``,
    `The opencode-veris plugin could not find its skill files on disk, so`,
    `this command cannot run. Tell the engineer the install is broken and to`,
    `reinstall with: opencode plugin opencode-veris -g --force`,
    `then restart opencode. Do nothing else.`,
  ].join("\n")
}

const VerisPlugin = async () => ({
  config: async (cfg) => {
    try {
      const skillsDir = findSkillsDir()
      cfg.command ??= {}
      for (const name of COMMANDS) {
        cfg.command[`veris:${name}`] ??= skillsDir
          ? {
              template: template(skillsDir, name),
              description: skillDescription(join(skillsDir, name, "SKILL.md")),
            }
          : {
              template: brokenTemplate(name),
              description: `veris ${name} (broken install: skill files missing)`,
            }
      }
      cfg.mcp ??= {}
      // Plugin-injected config gets no {env:...} substitution; real values only.
      cfg.mcp.veris ??= {
        type: "remote",
        url: (process.env.VERIS_API_BASE || "https://svc.api.veris.ai") + "/mcp",
        headers: { "X-API-Key": process.env.VERIS_API_KEY ?? "" },
        oauth: false,
      }
    } catch {
      // Never take opencode down; a failed registration surfaces in mcp list
      // and as a missing command, both recoverable by reinstalling.
    }
  },
})

export default VerisPlugin
