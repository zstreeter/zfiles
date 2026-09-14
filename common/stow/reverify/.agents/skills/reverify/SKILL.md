---
name: reverify
description: "Verify claims about binaries against the actual bytes using deterministic tools — VERIFIED/REFUTED/INCONCLUSIVE with evidence, plus a ledger that survives context resets. Use when analyzing an executable, object file, firmware or byte blob, or when asked to check a claim about compiled output."
---

# reverify

An anti-hallucination judge for claims about **binaries**. The model proposes;
a PE parser, a disassembler and a CPU emulator check the claim against the real
bytes and return `VERIFIED`, `REFUTED` or `INCONCLUSIVE` with evidence.

## Read this before reaching for it

Its scope is narrower than "deterministic verification" suggests. Every one of
its nine tools takes a **binary** as input: an executable, an object file,
firmware, a raw byte blob. Point it at a `.md`, a `.py` or a `.cc` and it has
nothing to say. It does not check prose, arithmetic, or whether code is correct.

Use it when the question is *"what is actually in these bytes?"* — and say so
plainly when the question is something else, rather than running it for the
appearance of rigor.

## Invocation — CLI only, and it may not be installed yet

There is **no MCP server registered**, in any harness. That is deliberate: an
MCP server's tool schemas ride in every request forever, and binary questions
are rare here, so it is a CLI you install when a real one shows up.

```bash
reverify-setup            # first, if `command -v reverify` comes up empty
reverify-setup --status   # is it installed, and where

reverify auto sample.bin --json          # start here when unsure
reverify parse-pe sample.exe --json
reverify parse sample.so --json          # ELF/Mach-O
reverify disasm 4889e5c3 --arch x86_64
reverify functions sample.bin --json
reverify verify sample.bin --claim '{…}'
reverify ledger sample.bin
```

`reverify-setup` builds a venv at `~/.local/share/reverify/venv` and symlinks
onto `PATH` — a venv rather than `pip install --user` because Ubuntu's Python is
PEP 668 externally-managed and none of these machines grant sudo. `--full` adds
capstone, unicorn, lief and z3, but builds from source on some platforms; if it
fails the pure-Python core still works.

If it needs installing, **say so and install it** rather than answering the
binary question from inference.

## The ledger

Verified facts are written to `.reverify/ledger/<sha256>.json`, keyed by the
binary's hash. They survive compaction, `/clear`, and a process restart.

So on resuming work on a binary, **run `reverify ledger <file>` first**. It
returns what was *proven* in an earlier session — including what was *refuted* —
rather than what you last believed. A summary carries forward conclusions; the
ledger carries forward evidence.

Write to it as you go, so a context reset mid-analysis is cheap.

For that same discipline applied to everything that *isn't* a binary —
benchmarks, memory profiles, hardware config, test results — see the `measure`
skill, which is the resident, always-on version of this idea.

## Trusting the verdicts

Spot-checked on a known ELF: `reverify auto /bin/ls` reported entrypoint
`0x6d30`, `x86_64`, 64-bit — matching `readelf -h` exactly.

Two honest limits:

- **PE is its strong suit.** On ELF the pure-Python backend returned an empty
  section and import list for a binary that plainly has both. Header-level facts
  were right; structural completeness was not. Don't read an empty list as
  "there are none" — cross-check with `readelf`/`objdump` before asserting it.
- **Optional engines change the answers.** `capstone`, `unicorn`, `lief` and
  `z3` are extras; without them some analyses fall back or return
  `INCONCLUSIVE`. `reverify backends` says what is actually loaded — check it
  before treating a negative result as meaningful.

Treat `REFUTED` as authoritative and correct yourself. Treat `INCONCLUSIVE` as
*unknown*, not as weak support for what you already thought.

## Related

- `measure` — the always-on counterpart: records what commands actually printed,
  so performance, memory and hardware claims are quoted rather than recalled.
- Research pipeline: `obsidian`, `quarto`, `pandoc`, `latex`, `zotero`.
