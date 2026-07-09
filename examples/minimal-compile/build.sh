#!/usr/bin/env bash
# examples/minimal-compile/build.sh — compile the lfric_atm science target on a built
# LFRic environment, and run its bundled example.
#
# THIS IS THE MINIMAL-COMPILE EXAMPLE. The reproducible core of this repo is the
# environment itself (Stage 1, scripts/build.sh). Compiling a science target is
# the smallest thing you do *with* that environment — copy and adapt this script
# for your own target. See examples/minimal-compile/README.md.
#
# It is also an INTEGRATION TEST of the built environment: it loads the env the
# way an end user does — `module load lfric-env/<version>/<variant>`, nothing
# more — and relies on that module to supply the whole toolchain. It deliberately
# does NOT know which Cray modules or compiler wrappers back a given variant; that
# is the modulefile's job (scripts/lfric-env.lua), baked in by Stage 1.
#
# It needs the private Met Office physics repos (casim, jules, socrates, ukca),
# vendored as pinned submodules under vendor/physics/ and fed to the LFRic extract
# step via PHYSICS_ROOT, so the compile clones nothing over SSH once those are
# initialised (see README). It uses an already-built environment for the
# variant you select; it does NOT build one.
#
# Set the variant + prefix EXPLICITLY to match the environment you built:
#   LFRIC_STACK=cray|spack   LFRIC_PREFIX=<the prefix you built into>
# (defaults: cray, and the same $PROJECTDIR/$USER/opt/<arch> default as Stage 1.)
set -uo pipefail

# This script lives in examples/minimal-compile/; the shared scripts are in scripts/.
_here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="${PIXI_PROJECT_ROOT:-$(cd -- "$_here/../.." && pwd)}"
SCRIPTS="$REPO_ROOT/scripts"

# common.sh sets REPO_ROOT/PREFIX/SPACK_ENV_DIR/MODULEFILE/MODULEPATH/...;
# activate.sh then module-loads the selected variant. (Runnable standalone.)
# shellcheck source=scripts/common.sh
. "$SCRIPTS/common.sh"
# shellcheck source=scripts/activate.sh
. "$SCRIPTS/activate.sh"

info() { echo "INFO: $*"; }
warn() { echo "WARN: $*" >&2; }
die()  { echo "ERROR: $*" >&2; exit 1; }

[ -f "$MODULEFILE" ] || die "Environment '$LFRIC_STACK' not built under PREFIX=$PREFIX. Build it first (Stage 1): ${LFRIC_STACK:+LFRIC_STACK=$LFRIC_STACK }sbatch scripts/build.sbatch  (set LFRIC_PREFIX to match if you customised it)"

# Ensure patches are applied (idempotent) — in particular the lfric_apps
# local-sources patch, so local_build.py uses the staged submodules in place (no
# clone/rsync/git-fetch). Stage 1 applies these too; re-assert for a standalone run.
bash "$SCRIPTS/patch-all.sh" || die "patch-all failed"

# Use the staged submodule source trees in place (the local-sources patch
# symlinks them); keep them pristine by not dropping __pycache__ into the tree.
export PYTHONDONTWRITEBYTECODE=1

# --- Load the built environment (exactly as an end user would) --------------
# Everything the compile needs from the environment now comes from the modulefile
# Stage 1 generated. `module load lfric-env/<version>/<variant>` puts rose/cylc/
# psyclone + the Spack view on PATH and sets the COMPLETE toolchain for the
# selected variant: FC/CXX/LDMPI (cray: ftn/CC; spack: the view's mpif90/mpic++),
# the Cray PE modules (cray) or the view's MPI wrappers (spack), and the view's
# FFLAGS/LDFLAGS (XIOS/HDF5/netCDF/shumlib .mod files + libs). This example adds
# NOTHING to that. It used to hand-roll the Cray module loads, FC/CXX/LDMPI and
# FFLAGS/LDFLAGS right here — duplicating (and liable to drift from) what the
# modulefile now owns; see scripts/lfric-env.lua. Removing that is the point of
# this example: it demonstrates that an end user needs only the `module load`.
#
# activate.sh (sourced above) already did the load quietly (the pixi path). Assert
# it took — the module sets FC — so a not-yet-built or broken env is a clear error
# here, not a cryptic compile failure later; retry loudly to surface the reason.
if [ -z "${FC:-}" ] && command -v module >/dev/null 2>&1; then
  module load "$MODULE_NAME" \
    || die "could not 'module load $MODULE_NAME' — is the '$LFRIC_STACK' env built? (Stage 1: ${LFRIC_STACK:+LFRIC_STACK=$LFRIC_STACK }sbatch scripts/build.sbatch)"
fi
: "${FC:?FC unset after loading $MODULE_NAME (the Stage-1 env for '$LFRIC_STACK'). Build it first: ${LFRIC_STACK:+LFRIC_STACK=$LFRIC_STACK }sbatch scripts/build.sbatch}"
command -v "$FC" >/dev/null 2>&1 \
  || die "toolchain compiler '$FC' (set by $MODULE_NAME) not on PATH — environment load incomplete"
info "Toolchain from $MODULE_NAME: FC=$FC LDMPI=${LDMPI:-?} CXX=${CXX:-?} — $("$FC" --version 2>/dev/null | head -1)"

APPS_ROOT_DIR="${APPS_ROOT_DIR:-$REPO_ROOT/vendor/lfric_apps}"
CORE_ROOT_DIR="${CORE_ROOT_DIR:-$REPO_ROOT/vendor/lfric_core}"
# PSyclone optimisation set: a dir under applications/lfric_atm/optimisation/.
# "minimum" is the Makefile's portable baseline (and its default); override with
# e.g. meto-ex1a for Cray-EX-tuned transforms. Upstream replaced the old
# -u/--target_platform flag with -p/PSYCLONE_TRANSFORMATION.
PSYCLONE_TRANSFORMATION="${PSYCLONE_TRANSFORMATION:-minimum}"
MAKE_JOBS="${MAKE_JOBS:-8}"
PROJECT="${PROJECT:-lfric_atm}"

# Physics sources: vendored, pinned submodules under vendor/physics/ instead of
# build-time SSH clones. lfric_apps' extract step (build/extract/extract_science.py,
# used for casim/ukca and the jules/socrates interfaces) reads $PHYSICS_ROOT/<dep>
# directly when PHYSICS_ROOT is set, skipping clone_and_merge entirely. lfric_core
# is supplied separately as a local path via -c below (also no network).
export PHYSICS_ROOT="${PHYSICS_ROOT:-$REPO_ROOT/vendor/physics}"
for _dep in casim jules socrates ukca; do
  [ -e "$PHYSICS_ROOT/$_dep/.git" ] \
    || die "physics submodule '$_dep' not initialised under $PHYSICS_ROOT. Init the physics submodules: git submodule update --init --jobs 4 -- vendor/physics/{casim,jules,socrates,ukca}  (or: pixi run init-physics)"
done
info "Physics sources (PHYSICS_ROOT): $PHYSICS_ROOT (casim/jules/socrates/ukca, pinned submodules)"

# local_build.py invokes `python`; ensure one exists on PATH.
PYTHON_BIN="${PYTHON:-}"
if [ -z "$PYTHON_BIN" ]; then
  if command -v python >/dev/null 2>&1; then PYTHON_BIN=python
  elif command -v python3 >/dev/null 2>&1; then
    _tmp_py="$(mktemp -d)"; ln -sf "$(command -v python3)" "$_tmp_py/python"
    export PATH="$_tmp_py:$PATH"; PYTHON_BIN=python
  else die "no python on PATH"; fi
fi

[ -f "$APPS_ROOT_DIR/build/local_build.py" ] || die "local_build.py not found in $APPS_ROOT_DIR/build"

if [ "${CLEAN_PHYSICS_SCRATCH:-1}" != "0" ]; then
  rm -rf "$APPS_ROOT_DIR/applications/lfric_atm/physics_scratch" \
         "$APPS_ROOT_DIR/applications/lfric_atm/working/physics_scratch"
fi

# local_build.py compiles in-place in the lfric_apps source tree. This working dir
# is SHARED across variants (and not per-variant), so build one variant at a time:
# two concurrent runs corrupt each other (stale handles, a locked dependency DB).
LOCAL_BUILD_WORKING_DIR="$APPS_ROOT_DIR/applications/lfric_atm/working"
LOCAL_BUILD_LOG="$PREFIX/lfric_atm-make.log"
[ "${CLEAN_BUILD_WORKING:-1}" != "0" ] && rm -rf "$LOCAL_BUILD_WORKING_DIR/build_lfric_atm"

build_lfric_atm() {
  local cmd=(
    "$PYTHON_BIN" "$APPS_ROOT_DIR/build/local_build.py" lfric_atm
    -c "$CORE_ROOT_DIR" -w "$LOCAL_BUILD_WORKING_DIR" -j "$MAKE_JOBS" -t build
    -p "$PSYCLONE_TRANSFORMATION"
  )
  [ "${VERBOSE_BUILD:-0}" = "1" ] && cmd+=(-v)
  ( cd "$APPS_ROOT_DIR" && "${cmd[@]}" ) |& tee "$LOCAL_BUILD_LOG"
  return "${PIPESTATUS[0]}"
}

info "Building lfric_atm (PSYCLONE_TRANSFORMATION=$PSYCLONE_TRANSFORMATION, -j $MAKE_JOBS)"
build_lfric_atm || die "local_build.py failed for lfric_atm. See $LOCAL_BUILD_LOG"

APP_BIN="$APPS_ROOT_DIR/applications/$PROJECT/bin/$PROJECT"
[ -x "$APP_BIN" ] || die "Executable not found at $APP_BIN"
info "Built: $APP_BIN"

EXAMPLE_DIR="$APPS_ROOT_DIR/applications/$PROJECT/example"
if [ -d "$EXAMPLE_DIR" ] && [ -f "$EXAMPLE_DIR/configuration.nml" ]; then
  info "Running example in $EXAMPLE_DIR"
  ( cd "$EXAMPLE_DIR" && "$APP_BIN" configuration.nml )
else
  warn "example configuration not found under $EXAMPLE_DIR; run $APP_BIN manually."
fi
echo "LFRIC_ATM_OK"
