---
name: remote-sandbox
description: Run commands on a remote GPU server through its agent sandbox -- an ssh alias ending in -agent whose every login lands in a hardened container. Use when work must run on a remote server, a *-agent ssh alias appears, or a sandbox login fails.
---

# remote-sandbox

While the human has a session open on a server, it has an ssh alias `<host>-agent`.
Its key is forced into one container there: every command, rsync and shell runs
**inside** it, never on the host. `ssh-sandbox list` prints the aliases.

## Running work

- `ssh <host>-agent '<command>'` -- runs in `/workspace`, as the human's uid, GPUs
  attached. `/workspace` (also `$HOME`) is the only writable path, and it lasts only
  until the human ends the session.
- `rsync -a ./ <host>-agent:/workspace/<dir>/` moves files in and out.
- For a repo's own ssh-driven runner, point its host variable at the
  `-agent` alias and its remote directory under `/workspace`.
- Inside, `AGENT_SANDBOX=1` and `AGENT_SANDBOX_IMAGE=<image>` are set: a repo's own
  launcher checks them to run directly instead of starting Docker, which the sandbox has none of.
- There is no network unless the human started the session with `--network bridge`:
  bring inputs in with rsync, and expect downloads to fail.
- The root filesystem is read-only and `/tmp` is a size-limited tmpfs: install
  with `pip install --target /workspace/<dir>` plus `PYTHONPATH` (images that ship a
  venv refuse `--user`).

## Long work: jobs

Anything that might outlive the connection runs as a job, never as a bare `ssh` command:
a dropped link kills a bare command, but not a job. Record the ID it prints -- it is
the only handle on the work after a reconnect.

- `ssh <host>-agent 'cd <dir> && agent-job start --name <id> -- <command>'` -- prints the ID
- `agent-job wait <id>` -- blocks, then exits with the job's code; re-run it after a drop
- `agent-job status <id>` -- `running`, `exited N`, `killed`, or `lost` (sandbox recreated)
- `agent-job logs <id> [-f]`, `agent-job ls`, `agent-job kill <id>`
- The human watches live with `ssh -t <host>-agent agent-job attach <id>`.

## When it refuses

`sandbox '<name>' is not running`, or `Permission denied (publickey)`, means no
session is open, its key expired, or (a session bound to the laptop's Tailscale
addresses) the connection did not come over the tailnet. Starting, ending and reconfiguring a session
is the human's step -- ask them to run `ssh-sandbox up <host> [opts]`. The sandbox
key cannot do it, by design. Ending a session deletes /workspace: tell the human
which results to keep before they run `ssh-sandbox down`.

On the laptop, under `agent-jail`, `Read-only file system` for a path in home means
it is outside the writable set (the directory the jail started in, plus
`~/.config/agent-jail/rw`): work in the project, or ask the human to list the path.

Lifecycle and the threat model: `ssh-sandbox --help`,
`agent-sandbox --help` (on the server), and the `sandbox` section of the zfiles README.
