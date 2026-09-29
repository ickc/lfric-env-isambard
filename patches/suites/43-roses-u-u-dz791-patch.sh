#!/usr/bin/env bash
# Stage the u-dz791 science suite -- the LFRic Atmosphere training course's idealised
# suite: a dynamics-only cloud-resolving model of a hydrogen atmosphere on a bi-periodic
# Cartesian domain -- for Isambard 3. The suite is NOT copied into this repo and NOT
# vendored: it is checked out from its real home, and this repo carries only the diff.
#
# UPSTREAM
#
#     https://code.metoffice.gov.uk/svn/roses-u/d/z/7/9/1/trunk   @ r368986
#     browse: https://code.metoffice.gov.uk/trac/roses-u/browser/d/z/7/9/1/trunk
#
# Denis Sergeev's suite (rose-suite.info: owner=denissergeev, "Copy of u-dv345"), used by
# the training's idealised practicals (source/modelling/idealised_practical_exercises/).
#
# Get it the way a Met Office scientist does. `rosie` ships in the environment Stage 1
# builds, with the `u-` prefix map, and `mosrs-cache-password` caches the password:
#
#     rosie checkout u-dz791            # -> ~/roses/u-dz791 (needs a MOSRS account)
#     svn update -r 368986 ~/roses/u-dz791
#
# Set LFRIC_SUITE_DIR to use a checkout somewhere else. The checkout MUST be at r368986 --
# a mismatch is a hard error, because that is the revision this patch was validated
# against; LFRIC_SUITE_REV overrides the pin for someone re-cutting deliberately.
#
# Two steps, in this order:
#
#   1. `rose app-upgrade` of app/lfric_atm and app/mesh from vn3.1 to vn3.2, the LFRic
#      release this environment builds. Upstream is on 2026.03.1, which the environment's
#      PSyclone 3.3 cannot build.
#   2. `git apply -p1` of 43-roses-u-u-dz791-isambard3.patch, the Isambard 3 port, cut
#      with `diff -ruN` against the UPGRADED tree -- 5 files, every hunk carrying an
#      `[isambard3]` comment saying what it replaced and why.
#
# The suite's SCIENCE is not in either step. It is two of Alex Corbett's lfric_apps
# branches, which upstream's dependencies.yaml merges from a clone on a Met Office machine.
# The public copies are based on 2026.03.1 and conflict on 2026.07.1, so they are
# supplied instead by patches/optional/33-lfric_apps-dz791-profile-init-patch.sh, which
# the staged suite's extract task applies to the tree it just cloned. See the note in
# dependencies.yaml.
#
# BOTH STEPS ARE SKIPPED, cleanly, when there is no suite here to patch at all -- no
# checkout, or no `rose` on PATH. Every OTHER missing precondition (the rose-meta the
# upgrade reads, a wrong revision, a patch that will not apply) is a HARD error, because
# run-suite.sh reads exit 0 as "staged" and would go on to `cylc vip` the UNPATCHED Met
# Office suite. It never half-applies. Idempotent: re-running is a no-op.
#
# This is NOT part of patch-all.sh's stack (it lives under patches/suites/, which
# patch-all's `-maxdepth 1` excludes) -- a suite checked out in the user's home is not
# something an environment build may quietly rewrite.
# examples/science-suites/run-suite.sh runs it.
set -o pipefail
_here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="${PIXI_PROJECT_ROOT:-$(cd "$_here/../.." && pwd)}"

SUITE_ID="u-dz791"
# The revision this patch was cut and validated against. Overridable, but only
# deliberately: see the revision check below.
SUITE_REV="${LFRIC_SUITE_REV:-368986}"
SUITE_URL="https://code.metoffice.gov.uk/svn/roses-u/d/z/7/9/1/trunk"
SUITE_DIR="${LFRIC_SUITE_DIR:-$HOME/roses/$SUITE_ID}"
PATCH_FILE="$_here/43-roses-u-u-dz791-isambard3.patch"
# The rose-meta version to upgrade to. Must match the LFRic the environment builds
# (vendor/lfric_apps is pinned at 2026.07.1 = vn3.2). Bump this when that pin moves.
SUITE_META_VN="${LFRIC_SUITE_META_VN:-vn3.2}"

info() { echo "INFO: $*"; }
warn() { echo "WARN: $*" >&2; }
fail() { echo "ERROR: $*" >&2; }

# --- preconditions ----------------------------------------------------------
if [ ! -d "$SUITE_DIR" ]; then
  warn "no $SUITE_ID checkout at $SUITE_DIR; skipping its site patch."
  warn "  Get it from MOSRS (needs a MOSRS account):"
  warn "    . examples/science-suites/site/activate-env.sh"
  warn "    rosie checkout $SUITE_ID && svn update -r $SUITE_REV $SUITE_DIR"
  warn "  ($SUITE_URL)"
  warn "  or point LFRIC_SUITE_DIR at an existing checkout."
  exit 0
fi
if ! command -v rose >/dev/null 2>&1; then
  warn "no 'rose' on PATH; skipping the $SUITE_ID patch entirely (both steps)."
  warn "  run-suite.sh activates the environment first, which is where it takes effect."
  exit 0
fi
[ -f "$PATCH_FILE" ] || { fail "site patch missing: $PATCH_FILE"; exit 1; }

# --- the revision this patch was cut against --------------------------------
# `svn info` on a working copy is local -- no network, no credentials. A mismatch is a
# HARD error, and it is checked HERE, before step 1: `rose app-upgrade` rewrites the
# checkout's app configs, so a wrong revision must be rejected while the tree is still
# pristine rather than left half-staged on an unvalidated baseline. To base on a
# different revision deliberately: LFRIC_SUITE_REV=<rev> (and re-cut the patch).
if command -v svn >/dev/null 2>&1 && [ -d "$SUITE_DIR/.svn" ]; then
  _rev="$(svn info --show-item revision "$SUITE_DIR" 2>/dev/null | tr -d '[:space:]')"
  if [ -n "$_rev" ] && [ "$_rev" != "$SUITE_REV" ]; then
    fail "$SUITE_DIR is at r$_rev; this patch was cut and validated against r$SUITE_REV."
    fail "  Nothing has been changed. Pin the checkout back:"
    fail "    svn update -r $SUITE_REV $SUITE_DIR"
    fail "  or base on r$_rev deliberately (re-cut the patch first -- see"
    fail "  examples/science-suites/$SUITE_ID/README.md, 'Regenerating the site patch'):"
    fail "    LFRIC_SUITE_REV=$_rev ..."
    exit 1
  fi
fi

# --- step 1: version alignment, via the native tool -------------------------
# rose needs the LFRic rose-meta packages. Honour an existing ROSE_META_PATH; otherwise
# build it from the vendored LFRic trees. ABSOLUTE paths only: upgrade_app runs `rose`
# from inside $SUITE_DIR/app, so a relative entry resolves against the wrong directory
# and rose fails with the unhelpful "[FAIL] Error: could not find meta flag".
if [ -z "${ROSE_META_PATH:-}" ]; then
  ROSE_META_PATH="$(find "$REPO_ROOT/vendor/lfric_apps" "$REPO_ROOT/vendor/lfric_core" \
                         "$REPO_ROOT/vendor/physics" \
                      -type d -name rose-meta 2>/dev/null | tr '\n' ':')"
  export ROSE_META_PATH
fi
# Test for jules-lfric specifically: `find` returns a list as soon as lfric_apps is
# initialised, so someone who ran `submodule-init` but not `init-physics` would sail past
# an emptiness check and hit a missing-rose-meta.conf traceback instead of this advice.
_have_jules_meta=false
IFS=':' read -r -a _meta_dirs <<< "$ROSE_META_PATH"
for _d in "${_meta_dirs[@]}"; do
  if [ -n "$_d" ] && [ -d "$_d/jules-lfric" ]; then _have_jules_meta=true; break; fi
done
if [ "$_have_jules_meta" != true ]; then
  fail "no jules-lfric rose-meta on ROSE_META_PATH; cannot upgrade $SUITE_ID's app configs."
  fail "  Nothing has been changed. Initialise the LFRic trees the meta comes from:"
  fail "    git submodule update --init vendor/lfric_apps vendor/lfric_core vendor/physics/jules"
  fail "  (or point ROSE_META_PATH at your own.)"
  exit 1
fi

upgrade_app() {
  local app="$1" conf="$SUITE_DIR/app/$1/rose-app.conf"
  [ -f "$conf" ] || { warn "no app/$app/rose-app.conf; skipping its upgrade."; return 0; }
  if grep -q "^meta=.*/${SUITE_META_VN}\$" "$conf"; then
    return 0   # already upgraded
  fi
  info "rose app-upgrade -C $app $SUITE_META_VN"
  ( cd "$SUITE_DIR/app" && rose app-upgrade -y -C "$app" "$SUITE_META_VN" >/dev/null ) \
    || { fail "rose app-upgrade failed for app/$app"; return 1; }
}
upgrade_app lfric_atm || exit 1
upgrade_app mesh      || exit 1

# --- step 2: the Isambard 3 site diff ---------------------------------------
# -p1 here, unlike u-dn704's -p0: that patch is `svn diff` against the pinned revision,
# this one is `diff -ruN a b` against the UPGRADED tree, because the upgrade in step 1 is
# deliberately not carried in the patch file.
apply_patch() { ( cd "$SUITE_DIR" && git apply -p1 "$@" "$PATCH_FILE" ); }
if apply_patch --reverse --check >/dev/null 2>&1; then
  exit 0   # already applied
fi
if ! apply_patch --check >/dev/null 2>&1; then
  fail "site patch does not apply to $SUITE_DIR."
  fail "  Most likely the checkout is not at r$SUITE_REV, step 1 upgraded to a different"
  fail "  rose-meta version than the patch expects (SUITE_META_VN=$SUITE_META_VN), or the"
  fail "  checkout has local edits."
  fail "    svn status $SUITE_DIR        # local edits?"
  fail "    svn revert -R $SUITE_DIR     # discard them and start clean"
  exit 1
fi
apply_patch || { fail "git apply failed"; exit 1; }
info "Applied the Isambard 3 site patch to $SUITE_ID (r$SUITE_REV) in $SUITE_DIR."
