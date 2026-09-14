"""Layered configuration, so one config tree serves machines that differ.

The layers, lowest priority first. Every one of them is optional -- a machine
with no config file at all gets DEFAULTS and works.

    1. DEFAULTS below
    2. ~/.config/paperctl/config.toml        committed to zfiles, no secrets
    3. its [target.<name>] section           wsl vs omarchy vs remote vs linux
    4. ~/.config/paperctl/local.toml         gitignored, per-host, holds secrets
    5. PAPERCTL_* environment variables
    6. CLI flags                             applied by cli.py, not here

Layer 3 is what makes one committed file describe several machines: the work
laptop reads mail through Microsoft Graph, the Omarchy box through himalaya,
and neither needs to know the other exists. Layer 4 is where an address or an
API key goes, because layer 2 is in a public repo.

Target detection mirrors bootstrap.sh:31-45 exactly, including its precedence
(remote > omarchy > wsl > linux). If the two ever disagree, a package would
stow under one name and configure itself under another.
"""

from __future__ import annotations

import os
import sys
import tomllib
from pathlib import Path

CONFIG_DIR = Path(
    os.environ.get("XDG_CONFIG_HOME") or Path.home() / ".config"
) / "paperctl"

# Not a nested dict: flat dotted keys make the env-var mapping ("library.root"
# -> PAPERCTL_LIBRARY_ROOT) mechanical, and make "did the user set this?" a
# single lookup rather than a walk.
DEFAULTS: dict[str, object] = {
    "library.root": "~/Library",
    "library.filename_style": "title_case",   # title_case | kebab | as_is
    "library.write_refs_bib": True,
    "library.write_readme": True,

    "sources.enabled": ["arxiv", "crossref", "openalex"],
    "sources.unpaywall_email": "",

    "mail.backend": "auto",                   # auto | graph | himalaya | none
    "mail.graph.token": "~/.config/microsoft-graph/token.json",
    "mail.himalaya.bin": "himalaya",
    "mail.himalaya.accounts": [],             # empty = himalaya's own default

    # Regexes for hosts private to this operator -- an intranet, a wiki behind
    # SSO. Empty by default and set in local.toml, because which hosts are
    # internal is a property of the machine, not of paperctl.
    "links.internal_domains": [],

    "quarto.projects_root": "~/research",
    "quarto.bib_name": "library.bib",

    "net.timeout": 30,
    "net.retries": 2,
    "net.user_agent": "paperctl/1.0 (+https://github.com/zstreeter/zfiles)",
}


def detect_target() -> str:
    """Which machine shape this is. Mirrors bootstrap.sh:31-45."""
    forced = os.environ.get("PAPERCTL_TARGET") or os.environ.get("ZFILES_TARGET")
    if forced:
        return forced.strip().lower()
    home = Path.home()
    # Order matters and is bootstrap's, not alphabetical. remote is never
    # sniffed there either -- a server looks like any other Linux box -- so it
    # only ever arrives through the environment, handled above.
    if (home / ".local/share/omarchy").is_dir() or (home / ".config/omarchy").is_dir():
        return "omarchy"
    try:
        if "microsoft" in Path("/proc/version").read_text().lower():
            return "wsl"
    except OSError:
        pass
    return "linux"


def _flatten(d: dict, prefix: str = "") -> dict[str, object]:
    """{'library': {'root': x}} -> {'library.root': x}, recursively."""
    out: dict[str, object] = {}
    for k, v in d.items():
        key = f"{prefix}{k}"
        if isinstance(v, dict):
            out.update(_flatten(v, f"{key}."))
        else:
            out[key] = v
    return out


def _read_toml(path: Path) -> dict:
    """A config file that does not parse is reported, never fatal.

    Losing the whole tool because one bracket is missing in an optional
    override file would violate the degrade-never-crash rule; the caller can
    still work from DEFAULTS.
    """
    try:
        with open(path, "rb") as fh:
            return tomllib.load(fh)
    except FileNotFoundError:
        return {}
    except (tomllib.TOMLDecodeError, OSError) as e:
        print(f"paperctl: ignoring {path}: {e}", file=sys.stderr)
        return {}


def _coerce(raw: str, like: object) -> object:
    """Env vars are strings; make them the shape the default says they are."""
    if isinstance(like, bool):
        return raw.strip().lower() in ("1", "true", "yes", "on")
    if isinstance(like, int) and not isinstance(like, bool):
        try:
            return int(raw)
        except ValueError:
            return like
    if isinstance(like, list):
        return [p.strip() for p in raw.split(",") if p.strip()]
    return raw


class Config:
    """Resolved settings, plus where each one came from.

    Provenance is kept because `paperctl doctor` has to answer "why is it using
    himalaya here?" -- and "because [target.omarchy] says so" is the useful
    answer, while printing the value alone is not.
    """

    def __init__(self, values: dict[str, object], origins: dict[str, str],
                 target: str, files: list[Path]):
        self._v = values
        self._origin = origins
        self.target = target
        self.files = files

    def get(self, key: str, default: object = None) -> object:
        return self._v.get(key, default)

    def origin(self, key: str) -> str:
        return self._origin.get(key, "default")

    def path(self, key: str) -> Path:
        """A config value that names a location, with ~ and $VARS expanded."""
        return Path(os.path.expandvars(str(self.get(key, "")))).expanduser()

    def section(self, prefix: str) -> dict[str, object]:
        p = prefix.rstrip(".") + "."
        return {k[len(p):]: v for k, v in self._v.items() if k.startswith(p)}

    def as_dict(self) -> dict[str, object]:
        return dict(self._v)


def load(overrides: dict[str, object] | None = None) -> Config:
    """Resolve every layer. `overrides` is layer 6 -- parsed CLI flags."""
    values = dict(DEFAULTS)
    origins = {k: "default" for k in values}
    target = detect_target()
    read: list[Path] = []

    # PAPERCTL_CONFIG=/dev/null is the documented way to run on defaults alone,
    # which is also how the flexibility tests pin behaviour.
    main = Path(os.environ["PAPERCTL_CONFIG"]).expanduser() if os.environ.get(
        "PAPERCTL_CONFIG") else CONFIG_DIR / "config.toml"

    for path, label in ((main, "config.toml"),
                        (CONFIG_DIR / "local.toml", "local.toml")):
        doc = _read_toml(path)
        if not doc:
            continue
        read.append(path)

        # [target.*] is peeled off before flattening: it is not settings, it is
        # a set of alternative settings, and only one of them applies here.
        targets = doc.pop("target", {}) if isinstance(doc.get("target"), dict) else {}
        for k, v in _flatten(doc).items():
            values[k] = v
            origins[k] = label
        for k, v in _flatten(targets.get(target, {})).items():
            values[k] = v
            origins[k] = f"{label} [target.{target}]"

    for k in list(values):
        env = "PAPERCTL_" + k.upper().replace(".", "_")
        if env in os.environ:
            values[k] = _coerce(os.environ[env], values[k])
            origins[k] = f"${env}"

    for k, v in (overrides or {}).items():
        if v is None:          # argparse fills unset flags with None
            continue
        values[k] = v
        origins[k] = "command line"

    return Config(values, origins, target, read)
