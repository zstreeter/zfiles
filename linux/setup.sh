# Plain Linux target: no package manager assumed. Sourced by bootstrap.sh;
# core CLI tools are backfilled via mise afterwards.
# shellcheck shell=bash

target_packages() {
    warn "Plain Linux — no package step. Core CLI tools are backfilled via mise below."
    command -v herdr &>/dev/null || curl -fsSL https://herdr.dev/install.sh | sh
}
