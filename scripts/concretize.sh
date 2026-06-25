#!/usr/bin/env bash
# concretize.sh — concretize the selected variant (the dependency SOLVE) and
# assert the resulting lock matches it.
#
# This is the SOLVE phase on its own — shared by build.sh (which then installs)
# and fetch.sh (which then downloads sources). Run it standalone as the cheap,
# login-node-safe check that a manifest/variant change still solves correctly,
# without the multi-hour install (this replaces the old STOP_AFTER_CONCRETIZE=1).
#
# The solve is single-process and idempotent: a no-op (~1s) when the lock already
# matches the manifest, re-solving only when the manifest changed. Set
# FORCE_CONCRETIZE=1 to force a fresh re-solve. Needs a Python in [3.7, 3.12)
# (module load cray-python/3.11.7, or use pixi).
set -uo pipefail

_here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=scripts/common.sh
. "$_here/common.sh"
# shellcheck source=scripts/lib.sh
. "$_here/lib.sh"

lfric_prepare
lfric_concretize

echo "CONCRETIZE_OK"
