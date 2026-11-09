---
name: remote-sandbox
description: Run commands on a remote GPU server through its agent sandbox -- an ssh alias ending in -agent whose every login lands in a jail on that server. Use when work must run on a remote server, a *-agent ssh alias appears, or a sandbox login fails.
---

# remote-sandbox

While the human has a session open on a server, it has an ssh alias `<host>-agent`.
Its key is forced into a jail there: every command, rsync and shell runs **inside**
it. `ssh-sandbox list` prints the aliases.

## Running work

- `ssh <host>-agent '<command>'` -- runs on the server, as the human's uid, GPUs
  visible, in `$HOME`: the session's workspace and the only writable path. It lasts
  only until the human ends the session. Your real home, `/var` and `/run` do not exist.
- `rsync -a ./ <host>-agent:<dir>/` moves files in and out (relative to the workspace).
- Use a repo's standard commands: point its host variable at the `-agent` alias and
  leave the rest. Never add sandbox-specific code to a repo -- if its standard
  commands fail in here, the sandbox is what needs fixing.
- `docker run` works as usual, for the session's images (`$AGENT_SANDBOX_IMAGE` is the
  first) and with `-v` sources inside the workspace. Privileged, `--cap-add`, host
  pid/net/user namespaces, other devices than GPUs, pull, build and exec are refused;
  the error says why. A human adds an image with `ssh-sandbox up <host> --image IMAGE`.
- There is no network unless the human started the session with `--network host`:
  bring inputs in with rsync, and expect downloads to fail.

## Long work: jobs

Anything that might outlive the connection runs as a job, never as a bare `ssh` command:
a dropped link kills a bare command, but not a job. Record the ID it prints -- it is
the only handle on the work after a reconnect.

- `ssh <host>-agent 'cd <dir> && agent-job start --name <id> -- <command>'` -- prints the ID
- `agent-job wait <id>` -- blocks, then exits with the job's code; re-run it after a drop
- `agent-job status <id>` -- `running`, `exited N`, `killed`, or `lost` (session restarted)
- `agent-job logs <id> [-f]`, `agent-job ls`, `agent-job kill <id>`
- The human watches live with `ssh -t <host>-agent agent-job attach <id>`.

## When it refuses

`sandbox '<name>' is not running`, or `Permission denied (publickey)`, means no
session is open, its key expired, or (a session bound to the laptop's Tailscale
addresses) the connection did not come over the tailnet. Starting, ending and reconfiguring a session
is the human's step -- ask them to run `ssh-sandbox up <host> [opts]`. The sandbox
key cannot do it, by design. Ending a session deletes the workspace: tell the human
which results to keep before they run `ssh-sandbox down`.

On the laptop, under `agent-jail`, `Read-only file system` for a path in home means
it is outside the writable set (the directory the jail started in, plus
`~/.config/agent-jail/rw`): work in the project, or ask the human to list the path.

Lifecycle and the threat model: `ssh-sandbox --help`,
`agent-sandbox --help` (on the server), and the `sandbox` section of the zfiles README.
