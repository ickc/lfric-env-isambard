#!/usr/bin/env bash
# stage-physics.sh — stage/update the pinned physics + lfric_core submodules to
# the refs in vendor/lfric_apps/dependencies.yaml.
#
# local_build.py no longer auto-clones the science sources (see
# patches/30-lfric_apps-local-sources-patch.sh): the build only reads what you
# have staged. This task is the EXPLICIT, reviewable, reproducible way to pull in
# new science instead of a silent build-time clone:
#
#   1. bump the ref(s) in vendor/lfric_apps/dependencies.yaml (or upstream)
#   2. pixi run stage-physics        # fetch + checkout each submodule to its ref
#   3. git add vendor/physics vendor/lfric_core && git commit   # pin the update
#
# Idempotent: re-running just re-asserts each submodule at its dependencies.yaml
# ref. Needs SSH access to the private Met Office repos (same as submodule-init).
set -uo pipefail

_here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=scripts/common.sh
. "$_here/common.sh"
info() { echo "INFO: $*"; }
warn() { echo "WARN: $*" >&2; }
die()  { echo "ERROR: $*" >&2; exit 1; }

DEPS="${DEPS_YAML:-$REPO_ROOT/vendor/lfric_apps/dependencies.yaml}"
[ -f "$DEPS" ] || die "dependencies.yaml not found at $DEPS — init the core submodules first: 'git submodule update --init -- vendor/lfric_apps' (or: pixi run submodule-init)"

# dependency name -> submodule path (lfric_core lives at vendor/, physics grouped)
declare -A PATHS=(
  [casim]="vendor/physics/casim"
  [jules]="vendor/physics/jules"
  [socrates]="vendor/physics/socrates"
  [ukca]="vendor/physics/ukca"
  [lfric_core]="vendor/lfric_core"
)

# Read the `ref:` value for a top-level key from the flat dependencies.yaml.
dep_ref() {
  awk -v d="$1:" '
    $1==d            { inb=1; next }
    /^[^[:space:]#]/ { inb=0 }
    inb && $1=="ref:" { print $2; exit }
  ' "$DEPS"
}

rc=0
for dep in casim jules socrates ukca lfric_core; do
  path="${PATHS[$dep]}"
  ref="$(dep_ref "$dep")"
  if [ -z "$ref" ]; then
    warn "$dep: no ref in dependencies.yaml; skipping"
    continue
  fi
  sub="$REPO_ROOT/$path"
  if ! git -C "$sub" rev-parse --git-dir >/dev/null 2>&1; then
    info "$dep: initializing submodule $path"
    git -C "$REPO_ROOT" submodule update --init -- "$path" \
      || { warn "$dep: submodule init failed (SSH access to the private repo?)"; rc=1; continue; }
  fi
  old="$(git -C "$sub" rev-parse --short HEAD 2>/dev/null || echo '?')"
  git -C "$sub" fetch --tags --quiet origin 2>/dev/null \
    || warn "$dep: fetch failed (offline?); will try existing objects"
  if git -C "$sub" -c advice.detachedHead=false checkout --quiet "$ref" 2>/dev/null; then
    new="$(git -C "$sub" rev-parse --short HEAD)"
    if [ "$old" = "$new" ]; then
      info "$dep ($path): already at $new  [ref $ref]"
    else
      info "$dep ($path): $old -> $new  [ref $ref]"
    fi
  else
    warn "$dep: could not checkout ref '$ref' (fetch it, or fix dependencies.yaml)"
    rc=1
  fi
done

if [ "$rc" -eq 0 ]; then
  echo "stage-physics: all submodules at their dependencies.yaml refs."
  echo "Review and commit the gitlinks: git add vendor/physics vendor/lfric_core && git commit"
else
  die "stage-physics: some submodules failed (see warnings above)"
fi
