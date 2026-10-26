/**
 * loadout — start each session with only the core tools; load groups on demand.
 *
 *   Header:  tools  core  ·  off: web research obsidian lens subagents   /load <group>
 *   /load <group>     /unload <group>     (the model can call load_tools itself)
 *
 * This trims what the model sees (the tool list in its prompt), not startup
 * time: Pi loads extension code once at launch. For that, scope packages per
 * project instead (see vault-template/.pi/settings.json for feynman).
 *
 * Any tool not matched by GROUPS is core and always on. Groups with no
 * registered tools (e.g. research outside a vault) are hidden.
 */

import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";
import { Type } from "typebox";

/** Group -> tool-name prefixes. Edit here to regroup. */
const GROUPS = {
	web: ["web_search", "fetch_content", "get_search_content", "source_check"],
	research: ["alpha_", "feynman_", "hf_"],
	obsidian: ["obsidian_"],
	lens: [
		"lens_diagnostics", "symbol_search", "effective_config", "project_report",
		"module_report", "read_symbol", "read_enclosing", "pi_lens_activate_tools",
	],
	subagents: ["subagent", "bg_wait", "contact_supervisor"],
	ask: ["ask_user_question"],
} satisfies Record<string, string[]>;
const NAMES = Object.keys(GROUPS) as (keyof typeof GROUPS)[];

/** Groups on in a fresh session. */
const DEFAULT_ON = ["ask"];

const ENTRY = "loadout";

export default function (pi: ExtensionAPI) {
	let on = new Set<string>(DEFAULT_ON);

	const groupOf = (tool: string) =>
		NAMES.find((g) => GROUPS[g].some((p) => tool.startsWith(p)));

	/** Groups that have at least one registered tool in this session. */
	const present = () => {
		const names = new Set<string>();
		for (const t of pi.getAllTools()) {
			const g = groupOf(t.name);
			if (g) names.add(g);
		}
		return NAMES.filter((g) => names.has(g));
	};

	function apply() {
		const active = new Set(pi.getActiveTools());
		for (const t of pi.getAllTools()) {
			const g = groupOf(t.name);
			if (!g) continue; // core: leave as the owning extension set it
			if (on.has(g)) active.add(t.name);
			else active.delete(t.name);
		}
		pi.setActiveTools([...active]);
	}

	function setHeader(ctx: ExtensionContext) {
		if (ctx.mode !== "tui") return;
		ctx.ui.setHeader((_tui, theme) => ({
			invalidate() {},
			render(): string[] {
				const groups = present();
				const loaded = ["core", ...groups.filter((g) => on.has(g))];
				const off = groups.filter((g) => !on.has(g));
				let line = `${theme.fg("dim", "tools")}  ${theme.fg("accent", loaded.join(" "))}`;
				if (off.length) line += theme.fg("dim", `  ·  off: ${off.join(" ")}   /load <group>`);
				return [line];
			},
		}));
	}

	function change(groups: string[], enable: boolean) {
		const known = present();
		const bad = groups.filter((g) => !known.includes(g));
		const ok = groups.filter((g) => known.includes(g));
		for (const g of ok) enable ? on.add(g) : on.delete(g);
		apply();
		pi.appendEntry(ENTRY, { on: [...on] });
		return { ok, bad, known };
	}

	pi.on("session_start", async (_event, ctx) => {
		// Restore this branch's last loadout; a fresh session gets DEFAULT_ON.
		on = new Set(DEFAULT_ON);
		for (const e of ctx.sessionManager.getBranch()) {
			if (e.type === "custom" && e.customType === ENTRY) on = new Set((e.data as { on: string[] }).on);
		}
		apply();
		setHeader(ctx);
	});

	const complete = (prefix: string) => {
		const hits = present().filter((g) => g.startsWith(prefix));
		return hits.length ? hits.map((g) => ({ value: g, label: g })) : null;
	};

	for (const [name, enable] of [["load", true], ["unload", false]] as const) {
		pi.registerCommand(name, {
			description: `${enable ? "Enable" : "Disable"} a tool group: /${name} <group...>`,
			getArgumentCompletions: complete,
			handler: async (args, ctx) => {
				const { ok, bad, known } = change(args.split(/\s+/).filter(Boolean), enable);
				if (bad.length || !ok.length)
					ctx.ui.notify(`groups: ${known.join(" ")}${bad.length ? `  (unknown: ${bad.join(" ")})` : ""}`, "warning");
			},
		});
	}

	pi.registerTool({
		name: "load_tools",
		label: "Load tools",
		description:
			`Enable an optional tool group for this session. Groups: ${NAMES.join(", ")} ` +
			"(web = web search/fetch; research = paper databases, vaults only; obsidian = notes; " +
			"lens = code navigation/diagnostics; subagents = delegation; ask = structured questions).",
		promptSnippet: "Enable an optional tool group (web, research, obsidian, lens, subagents, ask) when the task needs it",
		parameters: Type.Object({ group: Type.String({ description: "Group name" }) }),
		async execute(_id, params) {
			const { ok, known } = change([params.group], true);
			const text = ok.length
				? `Loaded ${params.group}; its tools are available from the next step.`
				: `Unknown group "${params.group}". Available: ${known.join(", ")}`;
			return { content: [{ type: "text", text }], details: {} };
		},
	});
}

