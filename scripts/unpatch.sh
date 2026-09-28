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
# An UNINITIALISED submodule is an empty directory, and `git -C <empty dir>
# rev-parse --git-dir` happily succeeds by walking UP to this repo -- at which
# point `reset --hard` + `clean -fd` would blow away the caller's uncommitted
# work in the whole checkout. (Measured: it does exactly that.) An initialised
# submodule has its own .git, so test for that file directly.
_lfric_submodule_present() { [ -e "$REPO_ROOT/vendor/$1/.git" ]; }

# Only the submodules that the patches here touch. Stage 1 patches its own
# vendored spack-packages and reverts it separately. (lfric_apps is patched by
# patches/30-lfric_apps-local-sources-patch.sh; lfric_egp_bench carries the u-dr932
# science suite and is staged by patches/40-*, so resetting it is also how you get
# that upstream suite back verbatim.)
#
# NOT here, and both deliberately:
#
#   patches/suites/* — u-dn704 and u-dt000 are MOSRS checkouts in the user's home,
#   not submodules. Their unpatch is the native one, in the checkout:
#       svn revert -R ~/roses/u-dn704
#   This script will not reach into $HOME.
#
#   patches/optional/* — those apply to a suite's freshly EXTRACTED source tree under
#   its cylc-run share/ directory, never to vendor/; `cylc clean` is what undoes them.
#   See patches/optional/README.md.
for sub in lfric_core lfric_apps lfric_egp_bench; do
  d="$REPO_ROOT/vendor/$sub"
  if _lfric_submodule_present "$sub"; then
    echo ">>> resetting vendor/$sub to pinned commit"
    git -C "$d" reset --hard
    git -C "$d" clean -fd
  else
    echo "skip vendor/$sub (not initialized)"
  fi
done
echo "unpatch complete: lfric_core, lfric_apps, lfric_egp_bench restored."
echo "(Stage 1's own patch reverts separately: git -C stage1/vendor/spack-packages checkout .)"
echo "    (u-dn704/u-dt000 are MOSRS checkouts: svn revert -R ~/roses/<suite>)"
