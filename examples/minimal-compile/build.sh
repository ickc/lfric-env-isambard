#!/usr/bin/env bash
# examples/minimal-compile/build.sh — compile the lfric_atm science target on a built
# LFRic environment, and run its bundled example.
#
# THIS IS THE MINIMAL-COMPILE EXAMPLE. The reproducible core of this repo is the
# environment itself (Stage 1, scripts/build.sh). Compiling a science target is
# the smallest thing you do *with* that environment — copy and adapt this script
# for your own target. See examples/minimal-compile/README.md.
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

# --- Toolchain + MPI/IO compiler wrappers ----------------------------------
# lfric_atm is compiled here directly via local_build.py (NOT through Spack), so
# this step needs the same MPI/IO stack as the active environment (LFRIC_STACK).
# Either way the compiler is gcc@14.3.0; LFRic's Makefiles require FC (fortran.mk
# errors if unset), LDMPI (the MPI linker; compile.mk has no default) and CXX.
#   cray  - Cray PE GNU stack. Loading PrgEnv-gnu is REQUIRED: it puts the Cray
#           compiler wrappers (ftn/cc/CC) on PATH and sets PE_ENV/CRAY_*. The
#           cray-hdf5-parallel/cray-netcdf-hdf5parallel modules make ftn/CC inject
#           the parallel HDF5/netCDF -I/-L/-l automatically (those are Cray
#           externals, not in the view — exactly how MPI is handled). PE_ENV=GNU
#           makes lfric.mk set CRAY_ENVIRONMENT so fortran/cxx.mk pick the
#           gfortran/g++ flag sets. FC/LDMPI=ftn, CXX=CC.
#   spack - from-source mpich + HDF5/netCDF, all in the env view. The MPI compiler
#           wrappers are the view's mpif90 + mpic++ (which wrap gfortran-14 /
#           g++-14); HDF5/netCDF/XIOS/shumlib come from the view via FFLAGS/
#           LDFLAGS below. No Cray modules; with PE_ENV unset, lfric.mk uses the
#           non-Cray profile. lfric_core picks its per-compiler flag set from the
#           wrapper LEAF NAME (fortran/<fc>.mk, cxx/<cxx>.mk): it ships mpif90.mk
#           and mpic++.mk, which each run `<wrapper> --version` and map the real
#           compiler (GNU) to gfortran.mk / g++.mk. So CXX must be `mpic++` — NOT
#           mpich's `mpicxx` alias, for which there is no cxx/mpicxx.mk.
if [ "$LFRIC_STACK" = cray ]; then
  PRGENV_MODULE="${PRGENV_MODULE:-PrgEnv-gnu}"
  CRAYPE_TARGET="${CRAYPE_TARGET:-craype-arm-grace}"
  HDF5_MODULE="${HDF5_MODULE:-cray-hdf5-parallel/1.14.3.9}"
  NETCDF_MODULE="${NETCDF_MODULE:-cray-netcdf-hdf5parallel/4.9.2.3}"
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
  module load "$HDF5_MODULE" "$NETCDF_MODULE" \
    || die "could not load $HDF5_MODULE / $NETCDF_MODULE — Cray ftn/CC wrappers cannot resolve HDF5/netCDF"
  if [ -z "${CRAY_MPICH_DIR:-}" ] || [ ! -d "${CRAY_MPICH_DIR:-/nonexistent}" ]; then
    die "CRAY_MPICH_DIR unset/missing after 'module load $PRGENV_MODULE' — Cray MPI wrappers cannot resolve"
  fi
  info "cray-mpich: $CRAY_MPICH_DIR (v${CRAY_MPICH_VERSION:-?})"
  info "cray HDF5/netCDF: ${HDF5_ROOT:-?} | ${NETCDF_DIR:-?}"
  export FC="${FC:-ftn}"
  export LDMPI="${LDMPI:-ftn}"
  export CXX="${CXX:-CC}"
else
  info "LFRIC_STACK=spack: compiling lfric_atm with the view's mpich wrappers (mpif90 + mpic++, wrapping gcc@14.3)"
  _mpifc=""; for _c in mpif90 mpifort; do command -v "$_c" >/dev/null 2>&1 && { _mpifc="$_c"; break; }; done
  [ -n "$_mpifc" ] || die "no mpich Fortran wrapper (mpif90/mpifort) on PATH — is the spack env built and active?"
  # CXX must be `mpic++`: lfric_core ships cxx/mpic++.mk (it runs the wrapper's
  # --version and maps GNU -> g++.mk) but no cxx/mpicxx.mk, so mpich's `mpicxx`
  # alias would fail at cxx.mk. mpif90.mk handles the Fortran side likewise.
  command -v mpic++ >/dev/null 2>&1 \
    || die "no mpich C++ wrapper 'mpic++' on PATH — is the spack env built and active? (cxx/mpic++.mk is the only MPI C++ profile lfric_core ships)"
  export FC="${FC:-$_mpifc}"
  export LDMPI="${LDMPI:-$_mpifc}"
  export CXX="${CXX:-mpic++}"
fi
info "MPI compiler: $("$FC" --version 2>/dev/null | head -1) (FC=$FC LDMPI=$LDMPI CXX=$CXX)"

# Spack-built libraries (XIOS, YAXT, shumlib, pFUnit, ...) live in the env view;
# the LFRic Makefiles locate them via FFLAGS (-I, for .mod files like xios.mod)
# and LDFLAGS (-L + -rpath, for libxios.a/libyaxt.so/...), mirroring the Met
# Office Spack build (rose-stem esnz cascade). The Cray ftn wrapper ignores
# CPATH/LIBRARY_PATH, so these MUST go through F/LDFLAGS. For the cray variant
# HDF5 and netCDF are NOT in the view (they are Cray externals): the cray-hdf5-
# parallel / cray-netcdf-hdf5parallel modules loaded above make the ftn/CC
# wrappers inject their -I/-L/-l automatically — exactly like mpi.mod and the MPI
# libs. For the spack variant HDF5/netCDF ARE in the view, so the same -I$view/
# include / -L$view/lib below already covers them. The lfric-env module (loaded
# by activate.sh) already put shumlib on LDFLAGS/LIBRARY_PATH/LD_LIBRARY_PATH;
# prepend the view's dirs here.
_view="$SPACK_ENV_DIR/.spack-env/view"
[ -d "$_view/include" ] || die "Spack env view missing at $_view — build Stage 1 first: ${LFRIC_STACK:+LFRIC_STACK=$LFRIC_STACK }sbatch scripts/build.sbatch"
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
