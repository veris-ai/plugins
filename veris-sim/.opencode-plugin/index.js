import { existsSync, readFileSync } from "node:fs"
import { dirname, join } from "node:path"
import { fileURLToPath } from "node:url"

const pkgDir = dirname(fileURLToPath(import.meta.url))
// Two lists, one role each. COMMANDS is what an engineer types as
// /veris-sim:<name>; SKILL_PATHS is what opencode loads as a skill the model
// may reach for on its own. They coincide today. tests/static.sh holds
// SKILL_PATHS to the skill directories (less veris-reference) and COMMANDS to
// a subset of SKILL_PATHS, so a skill can stop being a command, or a directory
// can be added, without either list drifting unnoticed.
const COMMANDS = ["setup", "build", "fix"]
const SKILL_PATHS = ["setup", "build", "fix"]

// This ships under the @veris-ai scope. opencode-veris-sim is the retired
// name: the final release under it is this same working plugin, which says so
// in every command description rather than breaking anyone still on it.
const PKG = "@veris-ai/veris-sim-opencode"
const RETIRED_PKG = "opencode-veris-sim"

// Published tarball carries skills/ beside this file (prepack copies it in);
// a git checkout has the tree one level up, at veris-sim/skills/.
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
//
// The absolute path is the instruction; the skill tool is the fallback for a
// session whose read tool runs somewhere this file is not. It is not the
// other way round because opencode keeps skills in one flat namespace by
// name, last write wins, and "setup", "build" and "fix" are the most
// collision-prone names there are. The path is unambiguous; the name is not.
function template(skillsDir, name) {
  const base = join(skillsDir, name)
  return [
    `The engineer invoked the veris-sim "${name}" command with arguments: $ARGUMENTS`,
    ``,
    `Read the file ${join(base, "SKILL.md")} now and follow it exactly,`,
    `treating the arguments above as its input. Relative paths inside that`,
    `file (reference/..., scripts/...) resolve against ${base}/, and links`,
    `of the form ../veris-reference/... or ../setup/reference/... resolve`,
    `against ${skillsDir}/.`,
    ``,
    `If that path cannot be read (your read tool runs somewhere this file is`,
    `not), load the skill named "${name}" with the built-in skill tool instead`,
    `and follow its body exactly. The files it lists must sit under ${base}/;`,
    `if they sit anywhere else, stop and say so: a different plugin's "${name}"`,
    `was loaded in place of this one.`,
  ].join("\n")
}

// The name in the tarball's own manifest -- always present, whatever `files`
// says. Undefined in odd installs, which reads as the current name.
function installedName() {
  try {
    return JSON.parse(readFileSync(join(pkgDir, "package.json"), "utf8")).name
  } catch {
    return undefined
  }
}

function brokenTemplate(name) {
  return [
    `The engineer invoked the veris-sim "${name}" command with arguments: $ARGUMENTS`,
    ``,
    `The ${PKG} plugin could not find its skill files on disk, so`,
    `this command cannot run. Tell the engineer the install is broken and to`,
    `reinstall with: opencode plugin ${PKG} -g --force`,
    `then restart opencode. Do nothing else.`,
  ].join("\n")
}

const VerisSimPlugin = async () => ({
  config: async (cfg) => {
    try {
      const skillsDir = findSkillsDir()
      // Shown wherever opencode lists the commands, which is where an engineer
      // on the retired name will see it.
      const moved =
        installedName() === RETIRED_PKG ? `[moved to ${PKG}] ` : ""
      cfg.command ??= {}
      for (const name of COMMANDS) {
        const desc = skillsDir
          ? skillDescription(join(skillsDir, name, "SKILL.md"))
          : undefined
        cfg.command[`veris-sim:${name}`] ??= skillsDir
          ? {
              template: template(skillsDir, name),
              description: moved ? moved + (desc ?? `veris-sim ${name}`) : desc,
            }
          : {
              template: brokenTemplate(name),
              description: `${moved}veris-sim ${name} (broken install: skill files missing)`,
            }
      }
      // The same files the commands read, registered so opencode loads them as
      // skills too: the commands stay for engineers who type them, the skills
      // let the model reach for one on its own.
      //
      // One path per skill, never the parent. skills.paths is scanned
      // recursively for **/SKILL.md, so registering skillsDir would also load
      // veris-reference -- a table of files the other three link to, not a
      // skill. opencode honours neither its user-invocable: false nor its
      // disable-model-invocation, so keeping it out is done here or not at all.
      if (skillsDir) {
        cfg.skills ??= {}
        cfg.skills.paths ??= []
        for (const name of SKILL_PATHS) {
          const dir = join(skillsDir, name)
          if (!cfg.skills.paths.includes(dir)) cfg.skills.paths.push(dir)
        }
      }
      // Plugin-injected config gets no {env:...} substitution; real values
      // only. No key, no server: a registration with an empty X-API-Key
      // would claim the `veris` name ahead of a plugin that has the key, and
      // show as failed in `opencode mcp list` either way.
      if (process.env.VERIS_API_KEY) {
        cfg.mcp ??= {}
        cfg.mcp.veris ??= {
          type: "remote",
          url: (process.env.VERIS_API_BASE || "https://svc.api.veris.ai") + "/mcp",
          headers: { "X-API-Key": process.env.VERIS_API_KEY },
          oauth: false,
        }
      }
    } catch {
      // Never take opencode down; a failed registration surfaces in mcp list
      // and as a missing command, both recoverable by reinstalling.
    }
  },
})

export default VerisSimPlugin
