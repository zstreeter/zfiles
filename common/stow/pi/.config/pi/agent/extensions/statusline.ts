/**
 * statusline — a Pi footer that mirrors the zsh/bash prompt.
 *
 * ─── Source of truth for the look ────────────────────────────────────────────
 *   ~/.config/shell/palette.sh
 *
 *   The same file the zsh and bash prompts source. Roles are read from it at
 *   extension load, so a re-theme is one edit there; `/reload` picks it up.
 *   PALETTE_DEFAULTS below mirrors that file so the footer still renders if it
 *   is missing — keep the two in sync when adding a role.
 *
 * ─── Layout ──────────────────────────────────────────────────────────────────
 *   prompt.sh's top line is `fill-line LEFT RIGHT`:
 *
 *     [user@host dir]                            (git)-[br:branch]
 *
 *   This footer keeps that shape:
 *
 *     [claude-sonnet-4 zfiles]              (pi)-[ctx:87%] (git)-[br:main]
 *
 *   ctx is the percentage of the context window REMAINING.
 *
 * To restyle, edit THEME. To change what appears and in what order, edit
 * LAYOUT. Everything below those two is mechanism.
 */

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { truncateToWidth, visibleWidth } from "@earendil-works/pi-tui";
import { readFileSync } from "node:fs";
import { homedir } from "node:os";
import { basename, join, resolve, sep } from "node:path";

// ─── Palette ─────────────────────────────────────────────────────────────────
// ANSI palette indices, equivalent to zsh's %B%F{n}. Staying on the palette
// rather than Pi's theme or hex means this footer follows the terminal
// colorscheme the same way the shell prompts do.

type Paint = (text: string) => string;

const RESET = "\x1b[0m";
const bold = (code: number): Paint => (t) => `\x1b[1;${code}m${t}${RESET}`;
const PLAIN: Paint = (t) => `\x1b[1m${t}${RESET}`; // %B%f — bold, default fg

const PALETTE_FILE = join(homedir(), ".config", "shell", "palette.sh");

/** Mirrors palette.sh; used verbatim when that file is absent or unreadable. */
const PALETTE_DEFAULTS: Record<string, number> = {
	ZF_PROMPT_BRACKET: 1,
	ZF_PROMPT_USER: 3,
	ZF_PROMPT_AT: 2,
	ZF_PROMPT_HOST: 4,
	ZF_PROMPT_DIR: 5,
	ZF_PROMPT_GROUP: 5,
	ZF_PROMPT_JOIN: 3,
	ZF_PROMPT_VALUE: 2,
	ZF_PROMPT_ALERT: 1,
	ZF_PROMPT_ENV: 6,
	ZF_PROMPT_ARROW: 4,
	ZF_PROMPT_CTX_OK: 2,
	ZF_PROMPT_CTX_WARN: 3,
	ZF_PROMPT_CTX_CRIT: 1,
};

/**
 * Read palette.sh without sourcing it. Only `NAME=digit` lines are recognised,
 * which is all that file is allowed to contain; anything else is ignored so a
 * malformed edit degrades to defaults instead of breaking the footer.
 */
function loadPalette(): Record<string, number> {
	const palette = { ...PALETTE_DEFAULTS };
	try {
		for (const line of readFileSync(PALETTE_FILE, "utf8").split("\n")) {
			const match = /^\s*(ZF_PROMPT_[A-Z_]+)=([0-7])\s*(?:#.*)?$/.exec(line);
			if (match?.[1] && match[2]) palette[match[1]] = Number(match[2]);
		}
	} catch {
		// Missing or unreadable: PALETTE_DEFAULTS keeps the footer rendering.
	}
	return palette;
}

const PALETTE = loadPalette();

/** Role name -> painter, via the palette index. 30 + n is the foreground SGR. */
const role = (name: string): Paint => bold(30 + (PALETTE[name] ?? 7));

// ─── THEME — which palette role each part of the footer uses ─────────────────

const THEME = {
	bracket: role("ZF_PROMPT_BRACKET"), // the [ ] around the left block
	model: role("ZF_PROMPT_USER"), // user slot
	provider: role("ZF_PROMPT_HOST"), // host slot (unused by default LAYOUT)
	dir: role("ZF_PROMPT_DIR"), // dir slot
	delim: role("ZF_PROMPT_GROUP"), // ( ) and [ ] of a right-side group
	dash: role("ZF_PROMPT_JOIN"), // the - joining ( ) to [ ]
	label: PLAIN, // the group name: pi, git
	branch: role("ZF_PROMPT_VALUE"),
	ctx: {
		ok: role("ZF_PROMPT_CTX_OK"),
		warn: role("ZF_PROMPT_CTX_WARN"),
		crit: role("ZF_PROMPT_CTX_CRIT"),
		unknown: role("ZF_PROMPT_CTX_WARN"), // "?" reads as a soft warning
	},
};

/** Thresholds on context *remaining*, in percent. */
const CTX_WARN = 30;
const CTX_CRIT = 10;

/** Widest model id before it is elided; keeps the left block prompt-sized. */
const MODEL_MAX = 28;

/**
 * Steps tried when the right side will not fit, longest first. Variable-length
 * group text (currently just the branch) is elided to each of these before any
 * group is dropped outright.
 */
const TEXT_STEPS = [Number.POSITIVE_INFINITY, 24, 16, 10];

// ─── LAYOUT — what appears, and in what order ────────────────────────────────
// `left` entries are joined with a space inside one pair of brackets.
// `right` entries each render as their own `(name)-[body]` group.
// Any entry returning undefined is dropped (e.g. git outside a repo).
//
// Right-side order is also retention order: when the row is too narrow, the
// LAST entry is dropped first. ctx leads because it is the one thing the shell
// prompt beside this footer cannot already tell you.

const LAYOUT = {
	left: ["model", "dir"],
	right: ["ctx", "git"],
} satisfies { left: SegmentName[]; right: GroupName[] };

// ─── Segment + group definitions ─────────────────────────────────────────────

interface State {
	model: string;
	provider: string;
	cwd: string;
	percent: number | null;
	branch: string | null;
}

/** Budget handed to groups whose text can be shortened before they are dropped. */
interface Budget {
	textMax: number;
}

type Segment = (s: State) => string | undefined;
type Group = (s: State, b: Budget) => { label: string; body: string } | undefined;

const SEGMENTS = {
	model: (s) => THEME.model(elide(s.model, MODEL_MAX)),
	provider: (s) => THEME.provider(s.provider),
	dir: (s) => THEME.dir(shortDir(s.cwd)),
} satisfies Record<string, Segment>;

const GROUPS = {
	ctx: (s) => ({ label: "pi", body: ctxBody(s.percent) }),
	git: (s, b) =>
		s.branch
			? { label: "git", body: THEME.branch(`br:${elide(s.branch, b.textMax)}`) }
			: undefined,
} satisfies Record<string, Group>;

type SegmentName = keyof typeof SEGMENTS;
type GroupName = keyof typeof GROUPS;

function ctxBody(percent: number | null): string {
	if (percent === null) return THEME.ctx.unknown("ctx:?");
	const remaining = Math.max(0, Math.round(100 - percent));
	const paint =
		remaining < CTX_CRIT
			? THEME.ctx.crit
			: remaining < CTX_WARN
				? THEME.ctx.warn
				: THEME.ctx.ok;
	return paint(`ctx:${remaining}%`);
}

/** `%1d`: last path component, but `~` for the home directory itself. */
function shortDir(cwd: string): string {
	const home = homedir();
	const path = resolve(cwd);
	if (path === home) return "~";
	if (path === sep) return sep;
	return basename(path);
}

function elide(text: string, max: number): string {
	return text.length <= max ? text : `${text.slice(0, max - 1)}…`;
}

// ─── Mechanism ───────────────────────────────────────────────────────────────

/** `(name)-[body]` — the vcs_info group shape. */
function renderGroup(label: string, body: string): string {
	return (
		THEME.delim("(") +
		THEME.label(label) +
		THEME.delim(")") +
		THEME.dash("-") +
		THEME.delim("[") +
		body +
		THEME.delim("]")
	);
}

function renderLeft(state: State): string {
	const parts = LAYOUT.left
		.map((name) => SEGMENTS[name](state))
		.filter((part): part is string => part !== undefined && part.length > 0);
	if (parts.length === 0) return "";
	return THEME.bracket("[") + parts.join(" ") + THEME.bracket("]");
}

function renderRight(state: State, names: GroupName[], budget: Budget): string {
	const groups = names
		.map((name) => GROUPS[name](state, budget))
		.filter((g): g is { label: string; body: string } => g !== undefined)
		.map((g) => renderGroup(g.label, g.body));
	// Trailing space keeps the block off the right edge, as ZLE_RPROMPT_INDENT
	// does for the real prompt.
	return groups.length > 0 ? `${groups.join(" ")} ` : "";
}

/**
 * Right-side renderings from most to least complete: elide variable text first,
 * then drop the lowest-priority group, and finally give up entirely.
 */
function* rightCandidates(state: State): Generator<string> {
	const names: GroupName[] = [...LAYOUT.right];
	while (names.length > 0) {
		for (const textMax of TEXT_STEPS) yield renderRight(state, names, { textMax });
		names.pop();
	}
	yield "";
}

/**
 * fill-line, but degrading instead of cliff-edging: zsh's version drops the
 * whole right part the moment it does not fit, which on a long branch name
 * costs you the context readout too.
 */
function fillLine(left: string, state: State, width: number): string {
	const leftWidth = visibleWidth(left);
	for (const right of rightCandidates(state)) {
		if (right.length === 0) break;
		const pad = width - leftWidth - visibleWidth(right);
		if (pad >= 1) return left + " ".repeat(pad) + right;
	}
	return truncateToWidth(left, width);
}

export default function (pi: ExtensionAPI) {
	pi.on("session_start", async (_event, ctx) => {
		ctx.ui.setFooter((tui, _theme, footerData) => {
			const unsubscribe = footerData.onBranchChange(() => tui.requestRender());

			return {
				dispose: unsubscribe,
				invalidate() {},

				render(width: number): string[] {
					if (width <= 0) return [""];
					const usage = ctx.getContextUsage();
					const state: State = {
						model: ctx.model?.id ?? "no-model",
						provider: ctx.model?.provider ?? "no-provider",
						cwd: ctx.cwd ?? process.cwd(),
						percent: usage?.percent ?? null,
						branch: footerData.getGitBranch(),
					};
					return [fillLine(renderLeft(state), state, width)];
				},
			};
		});
	});
}
