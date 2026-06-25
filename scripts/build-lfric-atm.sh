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

# No-pixi Stage-2 flow: when a lfric-env module is already loaded
# (`module load lfric-env/<variant>; bash scripts/build-lfric-atm.sh`) it exports
# SPACK_ENV=<working_dir>/spack-env/<variant>, which encodes BOTH the variant and
# the prefix the env was built under. common.sh (sourced below) would otherwise
# recompute these from its own defaults: LFRIC_STACK -> cray (wrong stack, or
# "Environment 'cray' not built") and WORKING_DIR -> the DEFAULT prefix, so
# MODULEFILE / SPACK_ENV_DIR / the view would point at a different tree than the
# one just loaded — fatal when the env was built under a custom LFRIC_PREFIX. So
# unless set explicitly, adopt both from SPACK_ENV. No-op under pixi or when set
# explicitly (e.g. LFRIC_STACK=spack ... / LFRIC_WORKING_DIR=... ). Only when the
# tail actually matches, so an unrelated SPACK_ENV cannot redirect us.
if [ -n "${SPACK_ENV:-}" ]; then
  _spack_env="${SPACK_ENV%/}"
  case "$_spack_env" in
    */spack-env/cray|*/spack-env/spack)
      [ -z "${LFRIC_STACK:-}" ]       && export LFRIC_STACK="${_spack_env##*/}"
      [ -z "${LFRIC_WORKING_DIR:-}" ] && export LFRIC_WORKING_DIR="${_spack_env%/spack-env/*}"
      ;;
  esac
  unset _spack_env
fi

# common.sh sets REPO_ROOT/SPACK_ENV_DIR/MODULEFILE/MODULEPATH/...; activate.sh
# then module-loads the env. (Runnable standalone, not only via pixi activation.)
# shellcheck source=scripts/common.sh
. "$_here/common.sh"
# shellcheck source=scripts/activate.sh
. "$_here/activate.sh"

info() { echo "INFO: $*"; }
warn() { echo "WARN: $*" >&2; }
die()  { echo "ERROR: $*" >&2; exit 1; }

[ -f "$MODULEFILE" ] || die "Environment '$LFRIC_STACK' not built. Run: ${LFRIC_STACK:+LFRIC_STACK=$LFRIC_STACK }pixi run build"

# Ensure patches are applied (idempotent). In particular this applies the
# lfric_apps local-sources patch so local_build.py uses the staged submodules in
# place (no clone/rsync/git-fetch). `pixi run build` also applies these, but
# build-lfric-atm.sh can be re-run on its own, so make it self-contained.
bash "$_here/patch-all.sh" || die "patch-all failed"

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
