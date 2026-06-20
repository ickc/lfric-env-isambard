#!/usr/bin/env bash
# build-lfric-atm.sh — compile lfric_atm and run its example.
#
# Separate from `build` because lfric_atm needs the private Met Office physics
# repos (casim, jules, socrates, ukca). Those are vendored as pinned submodules
# under vendor/physics/ and fed to the LFRic extract step via PHYSICS_ROOT, so
# the compile does NOT clone anything over SSH — it is offline/reproducible once
# `pixi run submodule-init` has populated them. The Spack environment from
# `pixi run build` is complete and usable without this step.
set -uo pipefail

_here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=scripts/activate.sh
. "$_here/activate.sh"

info() { echo "INFO: $*"; }
warn() { echo "WARN: $*" >&2; }
die()  { echo "ERROR: $*" >&2; exit 1; }

[ -f "$WORKING_DIR/env-runtime.sh" ] || die "Environment not built. Run: pixi run build"

# Ensure patches are applied (idempotent). In particular this applies the
# lfric_apps local-sources patch so local_build.py uses the staged submodules in
# place (no clone/rsync/git-fetch). `pixi run build` also applies these, but
# build-lfric-atm.sh can be re-run on its own, so make it self-contained.
bash "$_here/patch-all.sh" || die "patch-all failed"

# Use the staged submodule source trees in place (the local-sources patch
# symlinks them); keep them pristine by not dropping __pycache__ into the tree.
export PYTHONDONTWRITEBYTECODE=1

# --- Cray PrgEnv-gnu toolchain + cray-mpich --------------------------------
# lfric_atm is compiled here directly via local_build.py (NOT through Spack), so
# this step needs the same Cray PE GNU stack build.sh uses: gcc@14.3.0
# (gcc-native/14) + the system cray-mpich. Loading PrgEnv-gnu is REQUIRED: it
# puts the Cray compiler wrappers (ftn/cc/CC) on PATH and sets PE_ENV/CRAY_*.
# env-runtime.sh deliberately does NOT pin FC (the MPI compiler is the Cray ftn
# wrapper), so we load PrgEnv-gnu and set the MPI compiler vars here.
PRGENV_MODULE="${PRGENV_MODULE:-PrgEnv-gnu}"
CRAYPE_TARGET="${CRAYPE_TARGET:-craype-arm-grace}"
if ! command -v module >/dev/null 2>&1; then
  for f in /opt/cray/pe/lmod/lmod/init/bash /etc/profile.d/lmod.sh \
           /etc/profile.d/modules.sh /usr/share/lmod/lmod/init/bash; do
    # shellcheck source=/dev/null
    [ -f "$f" ] && . "$f" && break
  done
fi
command -v module >/dev/null 2>&1 \
  || die "no 'module' command found — cannot load $PRGENV_MODULE for the Cray ftn/cray-mpich wrappers"
module load "$PRGENV_MODULE" || die "could not 'module load $PRGENV_MODULE'"
module load "$CRAYPE_TARGET" 2>/dev/null \
  || warn "could not load $CRAYPE_TARGET (target may default to aarch64)"
if [ -z "${CRAY_MPICH_DIR:-}" ] || [ ! -d "${CRAY_MPICH_DIR:-/nonexistent}" ]; then
  die "CRAY_MPICH_DIR unset/missing after 'module load $PRGENV_MODULE' — Cray MPI wrappers cannot resolve"
fi
info "cray-mpich: $CRAY_MPICH_DIR (v${CRAY_MPICH_VERSION:-?})"

# LFRic's Makefiles require FC (fortran.mk errors if unset) and LDMPI (the MPI
# linker; compile.mk provides no default). On the Cray PE the MPI Fortran
# compiler/linker is the `ftn` wrapper (gfortran-14 + cray-mpich) and the C++ one
# is `CC`. PE_ENV=GNU makes lfric.mk set CRAY_ENVIRONMENT, so fortran/cxx.mk
# select the gfortran/g++ flag sets for those wrappers. (FPP comes from
# env-runtime.sh.)
export FC="${FC:-ftn}"
export LDMPI="${LDMPI:-ftn}"
export CXX="${CXX:-CC}"
info "MPI compiler: $("$FC" --version 2>/dev/null | head -1) (FC=$FC LDMPI=$LDMPI CXX=$CXX)"

# External libraries (XIOS, NetCDF, HDF5, YAXT, ...) are built by Spack and live
# in the env view. The LFRic Makefiles locate them via FFLAGS (-I, for the .mod
# files like xios.mod) and LDFLAGS (-L + -rpath, for libxios.a/libnetcdff.so/...),
# mirroring the Met Office Spack build (rose-stem esnz cascade). The Cray ftn
# wrapper ignores CPATH/LIBRARY_PATH, so these MUST go through F/LDFLAGS. (mpi.mod
# and the MPI libs come from the ftn wrapper itself.) env-runtime.sh already put
# shumlib on F/LDFLAGS/LD_LIBRARY_PATH; prepend the view's dirs here.
_view="$SPACK_ENV_DIR/.spack-env/view"
[ -d "$_view/include" ] || die "Spack env view missing at $_view — run: pixi run build"
export FFLAGS="-I$_view/include${FFLAGS:+ $FFLAGS}"
export LDFLAGS="-L$_view/lib -L$_view/lib64 -Wl,-rpath=$_view/lib -Wl,-rpath=$_view/lib64${LDFLAGS:+ $LDFLAGS}"
export LD_LIBRARY_PATH="$_view/lib:$_view/lib64${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
info "External libs (view): FFLAGS/LDFLAGS point at $_view"

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
    || die "physics submodule '$_dep' not initialized under $PHYSICS_ROOT — run: pixi run submodule-init"
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

LOCAL_BUILD_WORKING_DIR="$APPS_ROOT_DIR/applications/lfric_atm/working"
LOCAL_BUILD_LOG="$WORKING_DIR/lfric_atm-make.log"
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
