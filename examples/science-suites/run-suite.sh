#!/usr/bin/env bash
# examples/science-suites/run-suite.sh — launch an LFRic science-suite example on
# Isambard 3 against our built environment, the way a scientist does: with Cylc.
#
# THIS IS A SCIENCE-SUITE EXAMPLE. The reproducible core of this repo is the
# environment (Stage 1). Running a real Rose/Cylc suite is one thing you do *with*
# it. Unlike the env build + minimal-compile example (sbatch-driven), the
# science-suites are Cylc-driven: the
# scheduler runs here on the login node and submits each task (build/mesh/run) to
# Slurm itself, per the suite's own [directives]. We do NOT wrap it in sbatch.
#
# What this does:
#   1. Activates the built env (rose/cylc/psyclone + view on PATH) for the chosen
#      variant — so `cylc`/`rose` are the env's, matching what the suite tasks use.
#   2. Stages the suite, where it is a pinned submodule of its upstream repo:
#      `rose app-upgrade` to the LFRic version this env builds, then the Isambard 3
#      site patch. Idempotent; needs the env from step 1, hence the order.
#   3. Installs the Cylc site config (the `isambard3` Slurm platform + a roomy
#      cylc-run dir) via the repo's opt-in scripts/setup-cylc.sh.
#   4. Runs `cylc vip` (validate-install-play) on the suite, injecting LFRIC_STACK/
#      LFRIC_PREFIX/ACTIVATE_ENV so its tasks load our env.
#
# Usage:   bash examples/science-suites/run-suite.sh <suite-id> [cylc vip args...]
#   e.g.   bash examples/science-suites/run-suite.sh u-dr932   # cray env (the default)
# Watch:   cylc tui <suite-id>     /     cylc workflow-state <suite-id>
set -uo pipefail

_here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="${PIXI_PROJECT_ROOT:-$(cd -- "$_here/../.." && pwd)}"
SITE="$_here/site"

die()  { echo "ERROR: $*" >&2; exit 1; }
info() { echo "INFO: $*"; }

SUITE="${1:-}"
[ -n "$SUITE" ] || die "usage: run-suite.sh <suite-id> [cylc vip args...]  (e.g. u-dr932)"
shift || true

# Where each suite's Rose/Cylc tree lives, and what stages it. Two kinds:
#
#   u-dr932 is the UPSTREAM suite as a pinned submodule (vendor/lfric_egp_bench),
#   staged by a patch script exactly as Stage 1 stages its LFRic sources. Nothing
#   is copied into this repo, so the delta against what a scientist runs is a real
#   diff -- patches/40-lfric_egp_bench-u-dr932-isambard3.patch -- which is also
#   the pull request to send upstream.
#
#   u-dn704 and u-dt000 are still copies under examples/science-suites/. They will
#   move to the same mechanism when they are next re-validated.
case "$SUITE" in
  u-dr932)
    SUITE_DIR="$REPO_ROOT/vendor/lfric_egp_bench/src/suites/u-dr932"
    SUITE_PATCH="$REPO_ROOT/patches/40-lfric_egp_bench-u-dr932-patch.sh"
    ;;
  *)
    SUITE_DIR="$_here/$SUITE"
    SUITE_PATCH=""
    ;;
esac
if [ ! -d "$SUITE_DIR" ] && [ -n "$SUITE_PATCH" ]; then
  die "suite tree missing: $SUITE_DIR
       Initialise the submodule it lives in:
         git submodule update --init vendor/lfric_egp_bench"
fi
[ -d "$SUITE_DIR" ] || die "no such suite: $SUITE_DIR"

# common.sh sets PREFIX/MODULE*/LFRIC_STACK and respects LFRIC_PREFIX/LFRIC_STACK.
# shellcheck source=scripts/common.sh
. "$REPO_ROOT/scripts/common.sh"
[ -f "$MODULEFILE" ] || die "environment '$LFRIC_STACK' not built under PREFIX=$PREFIX. Build Stage 1 first: ${LFRIC_STACK:+LFRIC_STACK=$LFRIC_STACK }sbatch scripts/build.sbatch"

# 1. Activate the env so the launcher (and the detached scheduler it spawns) use
#    the env's cylc/rose. The suite tasks re-source this same file (ACTIVATE_ENV).
# shellcheck source=examples/science-suites/site/activate-env.sh
. "$SITE/activate-env.sh"
command -v cylc >/dev/null 2>&1 || die "no 'cylc' on PATH after activating env — is the '$LFRIC_STACK' variant built? (view should ship cylc)"
info "cylc $(cylc version 2>/dev/null) | rose $(rose version 2>/dev/null | awk '{print $2}') | variant=$LFRIC_STACK"

# 2. Stage the suite: `rose app-upgrade` to the version this env builds, then the
#    Isambard 3 site patch. Idempotent. It has to happen HERE rather than in
#    patch-all.sh because it needs the env's `rose`, which only exists after step 1
#    (patch-all.sh runs during the Stage-1 build, where the patch is inert).
if [ -n "$SUITE_PATCH" ]; then
  info "staging $SUITE: $(basename "$SUITE_PATCH")"
  bash "$SUITE_PATCH" || die "suite patch failed: $SUITE_PATCH"
fi

# 3. Cylc site config: the `isambard3` Slurm platform + a roomy cylc-run dir.
#    Reuse the repo's opt-in setup-cylc.sh (idempotent; writes ~/.cylc/flow).
bash "$REPO_ROOT/scripts/setup-cylc.sh" || die "setup-cylc.sh failed"

# `cylc install` runs the cylc.post_install.log_vc_info plugin, which shells out to
# `git diff` over the suite source. The staged suite is a PATCHED submodule, so that
# diff is never empty -- and a broken GIT_EXTERNAL_DIFF in the caller's environment
# then takes the whole install down with it (difft on aarch64 here dies with
# "<jemalloc>: Unsupported system page size"). Cylc only wants the diff for its own
# provenance log, so drop the external differ for the launch.
unset GIT_EXTERNAL_DIFF

# 4. Launch. Inject our env + source selection as Jinja template vars: flow.cylc
#    builds from $REPO_ROOT/vendor/* (the patched submodules), exports LFRIC_STACK/
#    LFRIC_PREFIX into the task env, and the ISAMBARD3 pre-script sources
#    ACTIVATE_ENV. The scheduler daemonises; watch with `cylc tui $SUITE`.
# NB: pass LFRIC_PREFIX=$BASE (the per-arch, UNVERSIONED base), NOT $PREFIX.
# common.sh treats LFRIC_PREFIX as the base and appends $LFRIC_ENV_VERSION itself
# (same contract as the sbatch scripts). Passing $PREFIX double-versions the path
# ($BASE/<ver>/<ver>), so activate-env.sh can't find the view and drops its
# -I<view>/include from FFLAGS — which makes the suite build depend on a racy
# copy of external .mod files (intermittent `Cannot open module file 'xios.mod'`).
# Pin the ENV VERSION into the workflow too: we validated the modulefile for THIS
# version (above), so the tasks must load the same one. Otherwise each task re-sources
# common.sh with no LFRIC_ENV_VERSION and reads the live ./VERSION — which can drift
# (an LFRIC_ENV_VERSION override at launch, or a VERSION bump while a long suite runs)
# and load a different lfric-env/<version>/<variant> than was launched.
info "cylc vip $SUITE_DIR --workflow-name $SUITE"
exec cylc vip "$SUITE_DIR" \
  --workflow-name "$SUITE" \
  -S "REPO_ROOT='$REPO_ROOT'" \
  -S "LFRIC_STACK='$LFRIC_STACK'" \
  -S "LFRIC_PREFIX='$BASE'" \
  -S "LFRIC_ENV_VERSION='$LFRIC_ENV_VERSION'" \
  -S "ACTIVATE_ENV='$SITE/activate-env.sh'" \
  "$@"
