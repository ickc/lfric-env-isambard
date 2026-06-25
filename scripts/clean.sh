#!/usr/bin/env bash
# clean.sh — remove the build output (WORKING_DIR, = PREFIX by default), guarded.
#
# WORKING_DIR is now deliberately OUTSIDE the repo (under PREFIX), so a plain
# `rm -rf "$WORKING_DIR"` is more dangerous than the old repo-local `rm -rf
# working_dir`: a mis-set LFRIC_WORKING_DIR/LFRIC_PREFIX could point at $HOME, a
# project/scratch root, or the repo itself. This refuses any target that is empty,
# not absolute, '/', or at/above a path we must never delete (the repo, $HOME,
# $PROJECTDIR, $SCRATCH). Deleting PREFIX itself (a descendant of those) is the
# intended case and is allowed.
set -uo pipefail

_here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=scripts/common.sh
. "$_here/common.sh"

die() { echo "ERROR: $*" >&2; exit 1; }

target="${WORKING_DIR:-}"
[ -n "$target" ]      || die "WORKING_DIR is empty — nothing safe to remove."
case "$target" in /*) ;; *) die "WORKING_DIR is not an absolute path: '$target'" ;; esac
[ "$target" != "/" ] || die "refusing to remove '/'."

# Strip any trailing slashes for the ancestor comparison below.
target="${target%/}"; [ -n "$target" ] || die "WORKING_DIR resolves to '/'."

# Refuse if $target is AT or ABOVE any protected path (i.e. removing it would take
# the repo / home / project / scratch root with it). Descendants are fine.
for crit in "$REPO_ROOT" "${HOME:-}" "${PROJECTDIR:-}" "${SCRATCH:-}"; do
  [ -n "$crit" ] || continue
  case "${crit%/}/" in
    "$target"/*) die "refusing: WORKING_DIR ($target) is at or above a protected path ($crit)." ;;
  esac
done

if [ ! -e "$target" ]; then
  echo "Nothing to clean: $target does not exist."
  exit 0
fi
echo "Removing build output: $target"
rm -rf -- "$target"
echo "Done."
