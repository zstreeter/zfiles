# Building the agent sandbox: mechanisms, layer by layer

How to build "agents run compute on remote servers over ssh, contained, leaving
nothing" from a few robust scripts and standard Linux/OpenSSH mechanisms. Each
mechanism cites its primary source and says whether it was **verified** on this
setup (laptop: WSL2, kernel 6.6, bubblewrap 0.9.0; server: Ubuntu 22.04,
kernel 6.8, OpenSSH 8.9, Docker 29.2.1, Podman 3.4.4, no `/etc/subuid` range,
no `sudo` assumed).

The threat runs through four layers. A weakness in an earlier layer bypasses
every later one, so they are listed in the order an agent meets them.

| Layer | Question | Mechanism | Status |
|---|---|---|---|
| 1. Laptop | Can the agent reach your real credentials? | bubblewrap jail around the agent | prototype verified |
| 2. SSH | What can the sandbox key do on the server? | `authorized_keys` options + a gate | built, verified |
| 3. Server | What can code in the sandbox reach? | Docker hardened (now) or Podman rootless | Docker verified; Podman partly |
| 4. Time | What survives a dropped link, and what is left after? | tmux jobs; session teardown | built, verified |

## 1. Laptop: keep the agent away from your real credentials

Today an agent on the laptop runs as you: it can read `~/.ssh/id_*`, use your
ssh-agent, and `ssh` straight past the sandbox. Nothing on the server can fix
that.

**Mechanism: bubblewrap.** Unprivileged; builds a mount namespace from command
line flags; uses `PR_SET_NO_NEW_PRIVS`. Its README: the protection "is entirely
determined by the arguments passed", `--new-session` is required unless
`TIOCSTI` is filtered (CVE-2017-5226), and "everything mounted into the sandbox
can potentially be used to escalate privileges". [bubblewrap][bwrap]

**Verified prototype** (~20 lines): `bwrap --dev-bind / / --new-session
--die-with-parent --unsetenv SSH_AUTH_SOCK --tmpfs ~/.ssh` then `--ro-bind` back
only `agent_sandbox`, `agent_sandbox.pub`, `config`, `config.d`, `known_hosts`,
plus `--tmpfs`/`--ro-bind /dev/null` over token stores (`~/.config/gh*`,
`~/.gnupg`, `~/.aws`, `~/.netrc`, `~/.docker`, `~/.config/shell/secrets.env`).
Inside: the real key unreadable, the ssh-agent unreachable, `ssh` to the real host
(real login) denied, `gh` tokens and `secrets.env` gone; HTTPS to the model API
still works.

**Escapes found in review (verified, then closed).** Hiding secrets is not enough
while the jail can ask something outside it to read them. With only the above, a
jailed `systemd-run --user --wait -P cat <hidden file>` printed it: the session bus
in `$XDG_RUNTIME_DIR` starts any command as you, unjailed (`systemctl --user`,
the keyring's Secret Service and the Wayland socket sit beside it; tmux and X11
sockets sit in `/tmp`). And a writable home let it plant `~/.zshrc` or a
`systemd --user` unit that runs outside the jail at your next login. Now the
runtime dir and `/tmp` are empty tmpfs, home is `--ro-bind` with only the current
directory and listed agent state writable, and `.git/{config,hooks}` read-only.
`/proc/<outside pid>/{root,environ}` were already refused (ptrace access check
across the user namespace). Verified on this laptop, and in `tests/unit.sh`.

Design choices to make when it becomes a script:

- **Denylist vs allowlist.** The prototype binds `/` and hides known secrets: easy,
  but a secret stored somewhere unlisted stays visible. The stronger form binds
  only what the agent needs (the project, the harness's config, toolchains) and
  nothing else. Start denylist, with a check that fails if a known secret path
  is readable inside.
- **Network stays shared.** Without `--unshare-net` the agent still reaches the
  internet and the host's abstract Unix sockets. Filtering needs the netns
  removed and a proxy bridged in by socket — what Anthropic's `srt` does with
  `socat` [srt]; `socat` is not installed here.
- **Wrap the whole harness, not one tool.** pi's own security guide: running pi
  "entirely inside a container, virtual machine, or sandbox" is "usually the
  strongest practical option"; a sandbox around built-in tools only leaves pi
  and its extensions outside (`pi-coding-agent/docs/security.md`).

**Defence in depth for the real key** (OpenSSH, no new software):
`ssh-add -c` (confirm each use via `ssh-askpass` — not installed here), `ssh-add
-h` (destination constraints), `ssh-add -t` (lifetime), or a FIDO `ed25519-sk`
key (touch per use). [ssh-add(1)][add], [ssh-keygen(1)][keygen]

## 2. SSH: what the sandbox key can do

**Mechanism: `authorized_keys` options** [sshd(8)][sshd]:
`restrict` (no forwarding, no pty, no `~/.ssh/rc`), `command=` (the client's
request arrives in `SSH_ORIGINAL_COMMAND`; applies to shell, command and
subsystem execution, i.e. sftp too), `expiry-time=` (OpenSSH 8.2+; **verified**:
8.9 rejects a `Z` suffix, takes server-local `YYYYMMDDHHMM`, and refuses a
backdated key), optionally `from=` (source addresses — unreliable from a laptop
whose address changes).

Built and verified as `agent-sandbox gate NAME`. The rules that make a gate safe:
- Never interpret `SSH_ORIGINAL_COMMAND` on the host; hand it to the container's
  shell as one argument.
- Take identity (which sandbox) from the key line, not from anything the client sends.
- Recognise sftp by the subsystem command sshd substitutes.

**Client side:** `IdentityFile` and forwards *accumulate* across matching `Host`
blocks, and a shared `ControlPath` reuses an existing login. Pin the alias
(`IdentitiesOnly`, `IdentityAgent none`, `ControlPath none`,
`ClearAllForwardings`) and verify with `ssh -G`, not by reading the config.
Built: `ssh-sandbox check`.

**At scale: certificates.** `ssh-keygen -s CA -V +8h -O force-command=...`;
a per-user `cert-authority` line trusts the CA without root, and a key's
`command=` must match a certificate's `force-command` exactly. [ssh-keygen(1)][keygen], [sshd(8)][sshd]
Marginal over `expiry-time` for a few hosts.

**Binding the key to one laptop: `from=` over Tailscale.** `authorized_keys`
`from="pattern-list"` makes sshd accept the key only from matching source
addresses (sshd(8), AUTHORIZED_KEYS FILE FORMAT). On the open internet or a LAN
the laptop's address moves, so it cannot be pinned; on a tailnet it is fixed per
device (`tailscale ip`) and WireGuard authenticates it, so a key copied off the
laptop opens nothing from another machine. `ssh-sandbox up` uses it when the
server is a tailnet peer (`tailscale ip -4 HOST` resolves) and there is no
ProxyJump (which would change the source address). Tailscale SSH was not used:
it authorizes by ACL, without `authorized_keys`, so there is no forced command
to put the gate in.

## 3. Server: what code in the sandbox can reach

### Docker, hardened (built, verified)

The OWASP Docker cheat sheet [owasp] mapped to the flags in use:

| OWASP rule | Here |
|---|---|
| #0 keep host and Docker updated | the admins' job: container escapes (runc CVE-2024-21626) land as root |
| #1 never expose `docker.sock` | not mounted; mount sources validated |
| #2 run as a non-root user | `--user $(id -u):$(id -g)` |
| #3 limit capabilities | `--cap-drop ALL` |
| #4 no privilege escalation | `--security-opt no-new-privileges` |
| #5 inter-container traffic | `--network none` by default |
| #6 Linux security module | Docker's default AppArmor profile (AppArmor on) |
| #7 limit resources | `--memory`, `--pids-limit`, `--shm-size`, tmpfs sizes |
| #8 read-only filesystem | `--read-only`, tmpfs `/tmp` |
| #6, seccomp | Docker's default profile; "not recommended to change" [seccomp] |
| #11 rootless mode | not available without the admins: see below |

**Residual risk:** the `docker` group. Rootless Docker needs ≥65,536 subordinate
UIDs in `/etc/subuid` [rootless]; `userns-remap` is a daemon-wide root
setting that also masks existing images [userns]. Neither is available here
without the admins.

### Podman rootless, single UID (partly verified)

Without a subuid range Podman maps one UID: container root = your UID on the host
(`uidmap=[{0 <your uid> 1}]`, **verified**), so an escape lands as you, not as root,
and no daemon or group is involved. **Verified** in a throwaway `$HOME`:
caps 0, `NoNewPrivs 1`, `--network none`, `--read-only`, and `/dev/kfd` plus the
render node open from inside (supplementary groups carry over; a rootless
namespace cannot drop them).

Costs, all real:
- Images with files owned by other UIDs fail to unpack ("potentially
  insufficient UIDs") unless storage sets `ignore_chown_errors = "true"`
  (**verified** needed). Those files then belong to the one mapped UID.
- With the `vfs` driver every image is a full copy. The workload image (~30 GB)
  lives in Docker's store and would need `docker save | podman load` each
  session (or a cache, which persists between sessions).
- Podman 3.4.4 is old; no systemd user session (no lingering), so it falls back
  to `cgroupfs` with warnings.
- **Not verified:** a real GPU compute run under Podman.

### bubblewrap on the host (available, not pursued)

`bwrap` is on the server too, and needs no daemon. But it runs the host's `/usr`,
not the workload image, so it suits only host-toolchain work.

## 4. Time: durability and teardown

- **Jobs that outlive the connection:** tmux sessions on a private socket inside
  the sandbox. Built and **verified**: a job outlived its attached client killed
  `-9`, and its exit code and log were kept.
  - `systemd-run --user` is not an option here: no lingering, no user D-Bus.
  - `dtach` and `abduco` are smaller alternatives, but not installed.
- **Nothing left behind:** a session directory plus a teardown that verifies the
  removal. Built and **verified**: nothing of the session's remained in `$HOME`
  except the `authorized_keys` mtime; no key line, no container; the Docker
  volume count was unchanged (`docker rm -v` drops anonymous volumes).
- **Audit (not built):** the gate runs on the host, outside the container. It can
  append each `SSH_ORIGINAL_COMMAND` to `~/.agent-sandbox/audit.log`, which the
  agent cannot write and `down --fetch` brings home before deleting it.

## 5. The scripts themselves

The bugs live testing found were mostly bash failure modes:
- `set -e` aborting inside a pipeline group;
- `grep -q` plus `pipefail` killing its writer with SIGPIPE;
- `env` cannot run shell functions;
- nested heredocs.

Mitigations, cheapest first:
- `shellcheck` in `common/githooks/check` (not installed here).
- Keep every behaviour under the existing fake-docker / fake-ssh unit tests, and
  mutate the code to prove each test can fail.
- Move the server half to Python stdlib if it grows. Python 3 is on both
  machines; bash stays the right tool for the thin wrappers.

## Proposed build

| Script | Where | Status |
|---|---|---|
| `agent-jail` | laptop | **new**: the bwrap wrapper of §1, with a self-check that known secret paths are unreadable inside |
| `ssh-sandbox` | laptop | built; add audit fetch |
| `agent-sandbox` | server, per session | built; add audit log; later `--runtime podman` once a GPU run passes |
| `agent-job` | in the sandbox | built |

Environment setup to go with them:
- `shellcheck` (and optionally `socat`, for network filtering in the jail).
- For the real key, `ssh-askpass` with `ssh-add -c`, or a FIDO key.

[bwrap]: https://github.com/containers/bubblewrap
[srt]: https://github.com/anthropic-experimental/sandbox-runtime
[add]: https://man.openbsd.org/ssh-add
[keygen]: https://man.openbsd.org/ssh-keygen#CERTIFICATES
[sshd]: https://man.openbsd.org/sshd#AUTHORIZED_KEYS_FILE_FORMAT
[owasp]: https://cheatsheetseries.owasp.org/cheatsheets/Docker_Security_Cheat_Sheet.html
[seccomp]: https://docs.docker.com/engine/security/seccomp/
[rootless]: https://docs.docker.com/engine/security/rootless/
[userns]: https://docs.docker.com/engine/security/userns-remap/

## Revision: a jail on the host, and the agent's docker through a proxy

A repo's standard runner calls `docker run`, which a container shell cannot do
without nesting. Re-creating the outer container's limits on the inner one
(path remapping, uid, groups, HOME, staged tools) was most of the code. So the
agent's shell is now a bubblewrap jail on the host -- an allowlisted filesystem
(no home, `/var` or `/run`, so no docker/containerd/lxd socket), its own pid,
ipc and network namespaces -- and its `docker` reaches the daemon only through
`agent-docker-proxy`, which refuses anything not on its list and rewrites only
the label, network `none`, and binds into a workspace volume Subpath (moby's
safepath then refuses symlink escapes). Containers run as the image says;
`down` chowns the workspace back. Verified on an 8-GPU server: the escape
list in the commit refused, and a GPU training repo ran unmodified.
