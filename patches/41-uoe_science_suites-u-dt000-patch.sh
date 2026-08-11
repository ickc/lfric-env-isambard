#!/usr/bin/env bash
# Target submodule: vendor/uoe_science_suites  (UniExeterRSE/Isambard3-LFRic-Env-Science-Suites)
#
# Stage the u-dt000 science suite -- LFRic Atm, Uranus/Neptune (ice giant)
# temperature and wind forcing -- for Isambard 3. Same arrangement as
# 40-lfric_egp_bench-u-dr932-patch.sh: the suite is NOT copied into this repo, it is
# a pinned submodule, so the difference between what a scientist runs and what runs
# here is a real diff rather than a described one.
#
# Two steps, in this order:
#
#   1. VERSION ALIGNMENT. The suite is written for LFRic vn2.2; this repo's
#      environment builds vn3.2. Rather than carry the mechanical diff, this RUNS
#      the native tool -- `rose app-upgrade -C <app> $LFRIC_SUITE_META_VN` -- over
#      the suite's app configs. The whole vn2.2 -> vn3.0 -> vn3.1 -> vn3.2 macro
#      chain applies cleanly, ~900 lines of namelist churn for lfric_atm and three
#      settings for mesh. Self-maintaining, and it keeps step 2 small enough to read.
#
#   2. SITE ADAPTATION. `git apply` of 41-uoe_science_suites-u-dt000-isambard3.patch,
#      touching seven files (flow.cylc, rose-suite.conf, meta/rose-meta.conf,
#      dependencies.yaml [new], app/git_extract_lfric, app/build_lfric_atm,
#      app/mesh, and a header comment on app/lfric_atm). That patch is the
#      reviewable artefact, and every hunk carries an `[isambard3]` comment saying
#      what it replaced and why. See examples/science-suites/u-dt000/README.md for
#      the itemised index.
#
# The suite's SCIENCE is not in either step. `theta_forcing='ice_giants_obs_like'`
# comes from Denis Sergeev's lfric_apps branch, forward-ported to vn3.2 by
# patches/optional/32-lfric_apps-ice-giants-forcing-patch.sh, which the staged
# suite's `git_extract_lfric` task applies to the tree it just cloned.
#
# BOTH STEPS ARE SKIPPED, cleanly, when their preconditions are absent -- the
# submodule not initialised, or `rose` not on PATH. That matters because
# patch-all.sh runs during the Stage-1 build, long before an environment exists to
# provide rose. examples/science-suites/run-suite.sh re-runs this script with the
# environment activated, which is where it actually takes effect. It never
# half-applies: if rose is missing, neither step runs.
#
# Idempotent: re-running is a no-op.
set -o pipefail
_here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="${PIXI_PROJECT_ROOT:-$(cd "$_here/.." && pwd)}"
WORKING_DIR="${LFRIC_SRC_ROOT:-$REPO_ROOT/vendor}"

# The rose-meta version to upgrade the suite's app configs to. Must match the
# LFRic the environment builds (vendor/lfric_apps is pinned at 2026.07.1 = vn3.2).
# Bump this when that pin moves.
SUITE_META_VN="${LFRIC_SUITE_META_VN:-vn3.2}"

SUITE_ROOT="$WORKING_DIR/uoe_science_suites"
SUITE_DIR="$SUITE_ROOT/suites/u-dt000"
PATCH_FILE="$_here/41-uoe_science_suites-u-dt000-isambard3.patch"

info() { echo "INFO: $*"; }
warn() { echo "WARN: $*" >&2; }
fail() { echo "ERROR: $*" >&2; return 1; }

# --- preconditions ----------------------------------------------------------
if [ ! -d "$SUITE_DIR" ]; then
  warn "vendor/uoe_science_suites not initialised; skipping the u-dt000 suite patch."
  warn "  git submodule update --init vendor/uoe_science_suites"
  exit 0
fi
if ! command -v rose >/dev/null 2>&1; then
  warn "no 'rose' on PATH; skipping the u-dt000 suite patch entirely (both steps)."
  warn "  It is applied by examples/science-suites/run-suite.sh, which activates the"
  warn "  environment first. Nothing is half-applied."
  exit 0
fi
[ -f "$PATCH_FILE" ] || { fail "site patch missing: $PATCH_FILE"; exit 1; }

# --- step 1: version alignment, via the native tool -------------------------
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

# rose needs the LFRic rose-meta packages. Honour an existing ROSE_META_PATH;
# otherwise build it from the vendored LFRic trees the environment is pinned to.
# NB vendor/physics is in the list and has to be: the vn2.2 -> vn3.0 macro pulls in
# the jules-lfric metadata, and without it the upgrade dies on a missing
# jules-lfric/vn7.9/rose-meta.conf.
if [ -z "${ROSE_META_PATH:-}" ]; then
  ROSE_META_PATH="$(find "$REPO_ROOT/vendor/lfric_apps" "$REPO_ROOT/vendor/lfric_core" \
                         "$REPO_ROOT/vendor/physics" \
                      -type d -name rose-meta 2>/dev/null | tr '\n' ':')"
  export ROSE_META_PATH
fi
if [ -z "$ROSE_META_PATH" ]; then
  warn "no rose-meta found under vendor/lfric_{apps,core}; skipping the u-dt000 patch."
  warn "  git submodule update --init vendor/lfric_apps vendor/lfric_core vendor/physics/jules"
  exit 0
fi

upgrade_app lfric_atm || exit 1
upgrade_app mesh      || exit 1

# --- step 2: the Isambard 3 site diff ---------------------------------------
if git -C "$SUITE_ROOT" apply --reverse --check -p1 "$PATCH_FILE" >/dev/null 2>&1; then
  exit 0   # already applied
fi
if ! git -C "$SUITE_ROOT" apply --check -p1 "$PATCH_FILE" >/dev/null 2>&1; then
  fail "site patch does not apply to $SUITE_ROOT."
  fail "  Most likely the submodule has moved off the pin this patch was made"
  fail "  against, or step 1 upgraded to a different rose-meta version than the"
  fail "  patch expects (SUITE_META_VN=$SUITE_META_VN). Regenerate it -- see"
  fail "  examples/science-suites/u-dt000/README.md, 'Regenerating the patch'."
  exit 1
fi
git -C "$SUITE_ROOT" apply -p1 "$PATCH_FILE" || { fail "git apply failed"; exit 1; }
info "Applied the Isambard 3 site patch to u-dt000."
