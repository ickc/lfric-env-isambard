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
#   2. Stages the suite where it lives — a pinned submodule (u-dr932) or a MOSRS
#      checkout (u-dn704, u-dt000): the Isambard 3 site patch, preceded by a
#      `rose app-upgrade` for the suites that still lag the environment's LFRic.
#      Idempotent; needs the env from step 1, hence the order.
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

# Where each suite's Rose/Cylc tree lives, what stages it, and how to get it if it is
# not there. Nothing is copied into this repo: each suite is the UPSTREAM tree, and this
# repo carries only a site diff (patches/…-isambard3.patch), which is therefore a real
# diff and directly the change to propose upstream.
#
# Two kinds of upstream, because the suites have two kinds of home:
#
#   u-dr932 is on GitHub, so it is a pinned submodule (vendor/lfric_egp_bench) staged
#   exactly as Stage 1 stages its LFRic sources.
#
#   u-dn704 and u-dt000 are Met Office rose suites and live in MOSRS subversion, which
#   is where rose workflows are staying (simulation-systems#566 moved the SOURCE
#   extraction to git, "not where the workflows themselves reside"). There is nothing to
#   vendor, so they are CHECKED OUT the way a Met Office scientist checks them out --
#   `rosie checkout` -- and the site patch is applied to that checkout. LFRIC_SUITE_DIR
#   overrides the location.
case "$SUITE" in
  u-dr932)
    SUITE_DIR="$REPO_ROOT/vendor/lfric_egp_bench/src/suites/u-dr932"
    SUITE_PATCH="$REPO_ROOT/patches/40-lfric_egp_bench-u-dr932-patch.sh"
    SUITE_GET="git submodule update --init vendor/lfric_egp_bench"
    ;;
  u-dt000)
    SUITE_DIR="${LFRIC_SUITE_DIR:-$HOME/roses/$SUITE}"
    SUITE_PATCH="$REPO_ROOT/patches/suites/41-roses-u-u-dt000-patch.sh"
    SUITE_GET="rosie checkout $SUITE && svn update -r 348703 \$HOME/roses/$SUITE
         (needs a MOSRS account; \`rosie\` comes from the env activated above)"
    ;;
  u-dn704)
    SUITE_DIR="${LFRIC_SUITE_DIR:-$HOME/roses/$SUITE}"
    SUITE_PATCH="$REPO_ROOT/patches/suites/42-roses-u-u-dn704-patch.sh"
    SUITE_GET="rosie checkout $SUITE && svn update -r 361458 \$HOME/roses/$SUITE
         (needs a MOSRS account; \`rosie\` comes from the env activated above)"
    ;;
  *)
    die "no such suite: $SUITE  (known: u-dn704, u-dr932, u-dt000)"
    ;;
esac

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

# 2. Stage the suite: the Isambard 3 site patch (and, for the suites that still lag the
#    environment's LFRic, a `rose app-upgrade` first). Idempotent. It happens HERE rather
#    than in patch-all.sh for two reasons: the upgrade needs the env's `rose`, which only
#    exists after step 1; and a suite checked out in the user's home is not something an
#    environment build may quietly rewrite.
#
#    Checked after activation, so the `rosie checkout` hint is a command you can run now.
[ -d "$SUITE_DIR" ] || die "no $SUITE tree at $SUITE_DIR
       Get it with:
         $SUITE_GET"
info "staging $SUITE: $(basename "$SUITE_PATCH")"
bash "$SUITE_PATCH" || die "suite patch failed: $SUITE_PATCH"

# 3. Cylc site config: the `isambard3` Slurm platform + a roomy cylc-run dir.
#    Reuse the repo's opt-in setup-cylc.sh (idempotent; writes ~/.cylc/flow).
bash "$REPO_ROOT/scripts/setup-cylc.sh" || die "setup-cylc.sh failed"

# `cylc install` runs the cylc.post_install.log_vc_info plugin, which records the source's
# version control state -- `svn info`/`svn diff` for the MOSRS checkouts, `git diff` for
# the submodule. The staged suite is always PATCHED, so that diff is never empty -- and on
# the git side a broken GIT_EXTERNAL_DIFF in the caller's environment then takes the whole
# install down with it (difft on aarch64 here dies with "<jemalloc>: Unsupported system
# page size"). Cylc only wants the diff for its own provenance log, so drop the external
# differ for the launch. Only meaningful for a git source, hence the repo test.
#
# Two ways to set one, so two steps. The env var we can just unset. `git config
# diff.external` -- the commoner difftastic install -- we cannot: there is no env
# override that means "unset", and setting it empty makes git try to run the empty
# string and die the same way. So probe instead, and only if the configured differ
# actually dies (git exits 128; a working one exits 0) point GIT_EXTERNAL_DIFF at
# `true`, which the env var half then wins with. That costs the provenance diff's
# content -- but only for a user whose differ was going to abort anyway.
unset GIT_EXTERNAL_DIFF
if git -C "$SUITE_DIR" rev-parse --git-dir >/dev/null 2>&1 &&
   ! git -C "$SUITE_DIR" diff >/dev/null 2>&1; then
  info "git diff.external is broken here; neutralising it for the cylc install"
  export GIT_EXTERNAL_DIFF=true
fi

# 4. Launch. Inject our env + source selection as Jinja template vars: REPO_ROOT lets the
#    extract task reach this repo's patch stack, LFRIC_STACK/LFRIC_PREFIX go into the task
#    env, and the root init-script sources ACTIVATE_ENV. The scheduler daemonises; watch
#    with `cylc tui $SUITE`.
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
