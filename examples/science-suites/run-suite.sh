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
#   2. Installs the Cylc site config (the `isambard3` Slurm platform + a roomy
#      cylc-run dir) via the repo's opt-in scripts/setup-cylc.sh.
#   3. Runs `cylc vip` (validate-install-play) on the suite, injecting LFRIC_STACK/
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
SUITE_DIR="$_here/$SUITE"
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

# 2. Cylc site config: the `isambard3` Slurm platform + a roomy cylc-run dir.
#    Reuse the repo's opt-in setup-cylc.sh (idempotent; writes ~/.cylc/flow).
bash "$REPO_ROOT/scripts/setup-cylc.sh" || die "setup-cylc.sh failed"

# 3. Launch. Inject our env + source selection as Jinja template vars: flow.cylc
#    builds from $REPO_ROOT/vendor/* (the patched submodules), exports LFRIC_STACK/
#    LFRIC_PREFIX into the task env, and the ISAMBARD3 pre-script sources
#    ACTIVATE_ENV. The scheduler daemonises; watch with `cylc tui $SUITE`.
info "cylc vip $SUITE_DIR --workflow-name $SUITE"
exec cylc vip "$SUITE_DIR" \
  --workflow-name "$SUITE" \
  -S "REPO_ROOT='$REPO_ROOT'" \
  -S "LFRIC_STACK='$LFRIC_STACK'" \
  -S "LFRIC_PREFIX='$PREFIX'" \
  -S "ACTIVATE_ENV='$SITE/activate-env.sh'" \
  "$@"
