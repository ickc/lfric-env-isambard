#!/usr/bin/env bash
# examples/science-suites/site/patch-sources.sh — apply this repo's LFRic-source
# patch stack to a suite's extracted source tree.
#
# The suite's `extract` task is the upstream Met Office one: merge_sources.py reads
# dependencies.yaml and clones each repo@ref into $SOURCE_ROOT. This runs after it,
# and is the only thing this repo adds to that step. It applies exactly the same
# patches/*-lfric_{core,apps}-*-patch.sh that the env build (Stage 1) and the
# minimal-compile example apply to vendor/, retargeted at $SOURCE_ROOT via
# LFRIC_SRC_ROOT. Two of them matter to a science suite:
#
#   30-lfric_apps-local-sources  the apps build otherwise re-clones its own science
#                                sources (casim/jules/socrates/ukca) DURING the
#                                compile, which can silently change the stack under
#                                a build the suite already pinned. Patched, it uses
#                                what PHYSICS_ROOT already points at.
#   31-lfric_apps-slow-physics-mphys-field  vn3.2 stopped creating the UM-physics
#                                mphys fields for a forcing-only config while
#                                slow_physics still fetched dtheta_mphys.
#
# The patches are idempotent and skip cleanly when a target file is absent, so they
# tolerate the suite building a different ref from the one this repo vendors.
#
# Usage:  patch-sources.sh <SOURCE_ROOT> [REPO_ROOT]
set -euo pipefail

SOURCE_ROOT="${1:?usage: patch-sources.sh <SOURCE_ROOT> [REPO_ROOT]}"
REPO_ROOT="${2:-${REPO_ROOT:-}}"

die()  { echo "ERROR: patch-sources: $*" >&2; exit 1; }
info() { echo "INFO: patch-sources: $*"; }

[ -d "$SOURCE_ROOT" ]      || die "no extracted source tree at $SOURCE_ROOT"
[ -n "$REPO_ROOT" ]        || die "REPO_ROOT not set (pass as \$2 or in the environment)"
[ -d "$REPO_ROOT/patches" ] || die "no patches/ under REPO_ROOT=$REPO_ROOT"

info "source tree: $SOURCE_ROOT"
shopt -s nullglob
n=0
for p in "$REPO_ROOT"/patches/*-lfric_core-*-patch.sh "$REPO_ROOT"/patches/*-lfric_apps-*-patch.sh; do
  info "apply $(basename "$p")"
  LFRIC_SRC_ROOT="$SOURCE_ROOT" bash "$p" || die "patch failed on $SOURCE_ROOT: $p"
  n=$((n + 1))
done
[ "$n" -gt 0 ] || die "no lfric_core/lfric_apps patches found under $REPO_ROOT/patches"

info "applied $n patch(es)"
echo "PATCH_SOURCES_OK"
