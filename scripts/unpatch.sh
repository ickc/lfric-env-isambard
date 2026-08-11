#!/usr/bin/env bash
# Revert all patches by restoring the patched submodules to their pinned state.
#
# Patches modify files inside three submodules (overwriting tracked files and
# creating new package directories). Resetting + cleaning each submodule returns
# it to exactly the pinned commit, undoing every patch at once.
set -uo pipefail

_here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=scripts/common.sh
. "$_here/common.sh"

# Only the submodules that patches touch. vendor/spack and the package repo
# mo-spack-packages are not patched. (lfric_apps is patched by
# patches/30-lfric_apps-local-sources-patch.sh; lfric_egp_bench and
# uoe_science_suites carry the u-dr932 and u-dt000 science suites and are staged by
# patches/40-* and patches/41-*, so resetting them is also how you get the upstream
# suites back verbatim.)
#
# NOT here: patches/optional/*. Those apply to a suite's freshly EXTRACTED source
# tree under its cylc-run share/ directory, never to vendor/ — `cylc clean` is what
# undoes them. See patches/optional/README.md.
for sub in lfric_core lfric_apps spack-packages lfric_egp_bench uoe_science_suites; do
  d="$REPO_ROOT/vendor/$sub"
  if git -C "$d" rev-parse --git-dir >/dev/null 2>&1; then
    echo ">>> resetting vendor/$sub to pinned commit"
    git -C "$d" reset --hard
    git -C "$d" clean -fd
  else
    echo "skip vendor/$sub (not initialized)"
  fi
done
echo "unpatch complete: lfric_core, lfric_apps, spack-packages, lfric_egp_bench, uoe_science_suites restored."
