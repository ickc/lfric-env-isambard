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

# Only the submodules that patches touch. lfric_apps and spack are not patched.
for sub in lfric_core simit-spack spack-packages; do
  d="$REPO_ROOT/vendor/$sub"
  if git -C "$d" rev-parse --git-dir >/dev/null 2>&1; then
    echo ">>> resetting vendor/$sub to pinned commit"
    git -C "$d" reset --hard
    git -C "$d" clean -fd
  else
    echo "skip vendor/$sub (not initialized)"
  fi
done
echo "unpatch complete: lfric_core, simit-spack, spack-packages restored."
