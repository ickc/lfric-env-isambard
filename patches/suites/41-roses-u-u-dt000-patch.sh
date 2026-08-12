#!/usr/bin/env bash
# Stage the u-dt000 science suite -- LFRic Atm with Uranus/Neptune (ice giant)
# temperature and wind forcing -- for Isambard 3. The suite is NOT copied into this repo
# and NOT vendored: it is checked out from its real home, and this repo carries only the
# diff.
#
# UPSTREAM
#
#     https://code.metoffice.gov.uk/svn/roses-u/d/t/0/0/0/trunk   @ r348703
#     browse: https://code.metoffice.gov.uk/trac/roses-u/browser/d/t/0/0/0/trunk
#
# Denis Sergeev's suite (rose-suite.info: owner=denissergeev, "Copy of u-dr931"). Rose
# workflows live in MOSRS subversion and are staying there -- MetOffice/simulation-systems
# discussion #566 moved the SOURCE extraction to git, explicitly "not where the workflows
# themselves reside" -- so there is no git upstream and nothing to vendor.
#
# Get it the way a Met Office scientist does. `rosie` ships in the environment Stage 1
# builds, and examples/science-suites/site/rose.conf gives it the `u-` prefix map:
#
#     rosie checkout u-dt000            # -> ~/roses/u-dt000 (needs a MOSRS account)
#     svn update -r 348703 ~/roses/u-dt000
#
# Set LFRIC_SUITE_DIR to use a checkout somewhere else.
#
# Two steps, in this order:
#
#   1. VERSION ALIGNMENT. Upstream is at vn3.0; this environment builds vn3.2. Rather
#      than carry the mechanical diff, this RUNS the native tool --
#      `rose app-upgrade -C <app> $LFRIC_SUITE_META_VN` -- over the suite's app configs.
#      Self-maintaining, and it keeps step 2 small enough to read. (u-dn704 needs no such
#      step: its upstream is already at vn3.2.)
#
#   2. SITE ADAPTATION. `git apply -p1` of 41-roses-u-u-dt000-isambard3.patch, which is
#      diffed against the UPGRADED tree and touches five files (flow.cylc,
#      rose-suite.conf, dependencies.yaml, app/extract, app/mesh). Every hunk carries an
#      `[isambard3]` comment saying what it replaced and why. See
#      examples/science-suites/u-dt000/README.md for the itemised index.
#
# The suite's SCIENCE is not in either step. `theta_forcing='ice_giants_obs_like'` comes
# from Denis' lfric_apps branch, which upstream's dependencies.yaml declares as a
# fork-merge -- correct in shape, but unusable at the release this environment builds
# (his branch is on vn3.0 and conflicts on 2026.07.1). It is supplied instead by
# patches/optional/32-lfric_apps-ice-giants-forcing-patch.sh, which the staged suite's
# extract task applies to the tree it just cloned. See the note in dependencies.yaml.
#
# BOTH STEPS ARE SKIPPED, cleanly, when their preconditions are absent -- no checkout, or
# no `rose` on PATH. It never half-applies. Idempotent: re-running is a no-op.
#
# This is NOT part of patch-all.sh's stack (it lives under patches/suites/, which
# patch-all's `-maxdepth 1` excludes) -- a suite checked out in the user's home is not
# something an environment build may quietly rewrite.
# examples/science-suites/run-suite.sh runs it.
set -o pipefail
_here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="${PIXI_PROJECT_ROOT:-$(cd "$_here/../.." && pwd)}"

SUITE_ID="u-dt000"
SUITE_REV="348703"
SUITE_URL="https://code.metoffice.gov.uk/svn/roses-u/d/t/0/0/0/trunk"
SUITE_DIR="${LFRIC_SUITE_DIR:-$HOME/roses/$SUITE_ID}"
PATCH_FILE="$_here/41-roses-u-u-dt000-isambard3.patch"
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

# `svn info` on a working copy is local -- no network, no credentials.
if command -v svn >/dev/null 2>&1 && [ -d "$SUITE_DIR/.svn" ]; then
  _rev="$(svn info --show-item revision "$SUITE_DIR" 2>/dev/null | tr -d '[:space:]')"
  if [ -n "$_rev" ] && [ "$_rev" != "$SUITE_REV" ]; then
    warn "$SUITE_DIR is at r$_rev; this patch was cut against r$SUITE_REV."
    warn "  svn update -r $SUITE_REV $SUITE_DIR   (or re-cut the patch -- see"
    warn "  examples/science-suites/$SUITE_ID/README.md, 'Regenerating the site patch')"
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
  warn "no jules-lfric rose-meta on ROSE_META_PATH; skipping the $SUITE_ID patch."
  warn "  git submodule update --init vendor/lfric_apps vendor/lfric_core vendor/physics/jules"
  exit 0
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
