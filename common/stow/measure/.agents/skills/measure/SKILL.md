---
name: measure
description: "Record and recall empirical results — benchmark numbers, memory profiles, hardware config, test outcomes — as captured command output with provenance and staleness detection, instead of recalling them from context. Use before asserting any performance, memory, timing or hardware fact, and after running anything that produced a number worth keeping."
---

# measure

A ledger of what commands **actually printed**. `measure run` executes the
command and captures the result, so an entry is a byproduct of execution rather
than a claim. Then `measure recall` gives back the number *with the commit it
was taken at* and a warning if the inputs have changed since.

## Two rules

1. **Before asserting a performance, memory, timing or hardware fact, run
   `measure recall <pattern>`.** If the ledger has it and it is `OK`, quote it
   and say when it was measured. If it is `STALE` or `?`, say so and re-run
   rather than quoting it. If it is absent, either measure it or say you do not
   know — do not supply a remembered figure.
2. **After running anything that produced a number worth keeping, record it.**
   Prefix the command with `measure run` rather than running it bare. A number
   that was not recorded is one you will confidently misremember after the next
   compaction.

## Recording

```bash
measure run --tag hbm-peak \
  --input src/residualMarginals.cc \
  -e 'peak_gb=Peak HBM: ([0-9.]+)' \
  -- ./build/bench --matrix-free --size 4096
```

Output streams live; nothing is swallowed. The exit code passes through, so this
composes inside scripts and Makefiles, and a **failed** run is recorded too —
a crash at a given size is evidence.

| flag | why it matters |
|---|---|
| `--tag` | the name you will recall by, and what `diff` compares across |
| `--input FILE` | records the file's hash. **This is the flag that makes staleness exact** — without it the ledger can only say "HEAD moved, something may have changed"; with it, it says "unchanged, still valid" or names what moved. Repeatable. Use it for the sources that actually feed the number. |
| `-e NAME=REGEX` | pulls a value out of the output (capture group 1). This is what turns a wall of profiler text into a comparable number. Repeatable. |
| `--note` | why the run was taken — future you will not remember |

## Recalling

```bash
measure recall hbm            # regex over tag, note, command, id
measure recall --latest       # current value of each tag, one line apiece
measure show hbm-peak         # newest entry for that tag, full output
measure diff hbm-peak         # last two runs: what moved, and by how much
measure recall --json         # for scripting
```

Statuses:

- **OK** — recorded inputs are byte-identical, or it was taken at the current
  clean commit. Safe to quote. Still say when it was measured.
- **STALE** — a recorded `--input` has changed. Names which. **Do not quote it.**
- **?** — unknown. Taken on a dirty tree, or at a different commit with no
  `--input` pinning. Might be fine; nothing here can tell you. Treat as unknown,
  not as weak support for what you already believed.
- **UNVERIFIED** — a `measure note`, not executed. Never present one of these as
  a measurement.

## Notes, and why they are marked

```bash
measure note --tag arch --source lscpu.txt:12 "64 physical cores across 2 sockets"
```

For facts learned by reading rather than running. They are stored with
`kind: note` and print as `UNVERIFIED` everywhere, so they can never be
confused with something that was executed. Prefer `measure run` whenever a
command could have produced the fact — `measure run --tag arch -- lscpu` beats
a note about what `lscpu` would have said.

## Where it lives

`<repo-root>/.measurements/ledger.jsonl` — append-only JSONL, one entry per
line, next to the code it describes. Override with `$MEASURE_DIR`. `measure
path` prints it.

Append-only is deliberate: the history is often the finding. A number that moved
across three commits tells you more than its current value. `measure prune`
exists but refuses to delete without `--yes` and backs the ledger up first.

Committing `.measurements/` is reasonable and often useful — it is a record of
what was observed on which machine at which commit, which is exactly what a
teammate or a reviewer wants. It contains captured stdout, so on a repo with
secrets in program output, gitignore it instead.

## What this is not

It does not check whether a number is *correct*, only that it is what the
command printed on that day at that commit. Garbage in, faithfully recorded
garbage out. Its whole job is removing the gap between "I measured this" and
"I remember measuring this".

## Related

- `reverify` — the same discipline for claims about **binaries**: verifies
  against the actual bytes. Install-on-demand CLI, not registered as an MCP
  server.
