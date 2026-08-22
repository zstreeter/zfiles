// Expose every skill in ~/.agents/skills as a slash command (/wayfinder,
// /grill-with-docs...). opencode already loads the skills for its `skill`
// tool but registers no command for them. Runs at startup, so skills added
// by `npx skills add` show up on the next launch with nothing to re-run.
import { readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { homedir } from "node:os";

export const SkillCommands = async () => ({
  config: async (config) => {
    const dir = join(homedir(), ".agents", "skills");
    config.command ??= {};
    let names = [];
    try { names = readdirSync(dir); } catch { return; }
    for (const name of names) {
      if (config.command[name]) continue;
      let md;
      try { md = readFileSync(join(dir, name, "SKILL.md"), "utf8"); } catch { continue; }
      const description = md.match(/^description:\s*(.+)$/m)?.[1]?.slice(0, 120) ?? `${name} skill`;
      config.command[name] = {
        description,
        template: `Load the \`${name}\` skill with the skill tool and follow it exactly. Arguments: $ARGUMENTS`,
      };
    }
  },
});
