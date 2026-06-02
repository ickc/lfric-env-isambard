#!/usr/bin/env bash
# Apply every patches/*-patch.sh in deterministic (sorted) order.
#
# Patch scripts are discovered dynamically (not hardcoded). Each is idempotent,
# so this can be re-run safely. `pixi run unpatch` reverts them by resetting the
# patched submodules.
set -uo pipefail

_here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=scripts/common.sh
. "$_here/common.sh"

PATCH_DIR="$REPO_ROOT/patches"
rc=0
while IFS= read -r -d '' f; do
  echo ">>> applying $(basename "$f")"
  if ! bash "$f"; then
    echo "ERROR: patch failed: $f" >&2
    rc=1
    break
  fi
done < <(find "$PATCH_DIR" -maxdepth 1 -name '*-patch.sh' -print0 | sort -z)

if [ "$rc" -eq 0 ]; then
  echo "All patches applied."
fi
exit "$rc"
