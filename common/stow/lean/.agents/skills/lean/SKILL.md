---
name: lean
description: "Lean 4 + Mathlib: the shared proof sandbox, starting a formalisation project, checking a proof, and the validation ladder for AI-written proofs. Use when formalising a lemma, checking a derived claim in Lean, a Lean build fails, or a proof must be trusted."
---

# Lean

Lean is the referee that is not the same model. A derived-by-us lemma that a
plan depends on is formalised and checked here before it counts as proved.

## Layout (installed by zfiles)

| piece | where | how |
|---|---|---|
| elan (toolchain manager) | `$ELAN_HOME` = `$XDG_DATA_HOME/elan` | bootstrap, every target |
| shared sandbox (Mathlib project) | `lean-sandbox path` | `lean-sandbox init`, once per machine (~5 GB) |
| scratch files | `$(lean-sandbox path)/Scratch/` | any `.lean` file anywhere also works with `check` |
| agent tools | MCP server `lean-lsp` (`uvx lean-lsp-mcp`) | `lean-sandbox mcp` (pi, Claude Code, Codex); opencode via its zfiles `opencode.json`; restart the harness (`/reload` in pi) |

The toolchain version is per project (`lean-toolchain` file); elan fetches it on
first `lake` call. Projects pinned to Mathlib use Mathlib's toolchain.

## Steps

1. **Scratch first.** Write the statement in `Scratch/<Topic>.lean` with
   `import Mathlib`, proof `by sorry`, and `#print axioms <thm>` after it.
   Get the *statement* right before the proof: the statement is the claim;
   a proof of the wrong statement proves nothing. Docstring cites the source:
   `/-- research/17 §5b; @kakaralaBisSouPha2009 eq. 9 -/` (the citekey must be in
   `~/Library` -- file the paper with `paperctl add`).
2. **Iterate with the MCP tools** (`lean_goal`, `lean_diagnostic_messages`,
   `lean_leansearch` / `lean_loogle` to find Mathlib lemmas, `lean_multi_attempt`
   to try tactics). Search Mathlib before proving a standard fact.
3. **Check.** `lean-sandbox check FILE` -- PASS requires: compiles, no `sorry`, a
   `#print axioms` line, and only `propext`, `Classical.choice`, `Quot.sound`.
   *Done when:* PASS, and a second reader agrees the Lean statement says what the
   informal claim says.
4. **Promote** a result worth keeping into a real project:
   `lean-sandbox new <Name> <repo-or-vault-dir>` (git repo, Mathlib cached), move the
   file, `lake build`. Commit `lean-toolchain` and `lake-manifest.json`; never commit
   `.lake/`.

## Validation ladder (lean-lang.org/doc/reference/latest/ValidatingProofs)

Pick the rung by how much the proof's author is trusted. AI-written proofs that a
claim rests on are *untrusted*: climb to rung 4.

1. `lake build` clean -- no errors, no `sorry` warnings in the module.
2. `#print axioms thm` -- only the three standard axioms (`lean-sandbox check`).
   `sorryAx` = incomplete; `*_native*` = native evaluation trusted; anything else =
   a custom axiom the result is relative to.
3. `lean4checker --fresh <Module>` -- replays the stored proofs through the kernel.
4. `lake comparator` (core Lean ≥ v4.35, with `lake check`) -- a trusted *challenge
   file* holding only the statement, judged against the proof built in a sandbox.
   The gold standard; it is what Anthropic used for the zeta-zeros formalisation.

## Gotchas

- First `lake build` after `new` compiles nothing heavy only if `lake exe cache get`
  ran; `lean-sandbox new/init/update` always fetch it. Mathlib from source = hours.
- `import Mathlib` in the sandbox costs seconds of load; fine for scratch, but a
  promoted project imports only the modules it uses.
- After `lean-sandbox update`, broken scratch files are expected: Mathlib renames
  lemmas. Fix by searching the new name (`lean_leansearch`).
- WSL: keep projects on the Linux filesystem, never under `/mnt/c` (lake is
  I/O-heavy).
