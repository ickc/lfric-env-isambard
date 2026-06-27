#!/usr/bin/env bash
# examples/science-suites/site/activate-env.sh — the ACTIVATE_ENV a science-suite
# task SOURCES to put our built environment on the toolchain. It is the
# analogue of the upstream env_lfric/activate.sh, but built on OUR Lmod modulefile
# (Stage 1) rather than a raw `spack env activate`.
#
# A Cylc/Rose suite task runs in a clean shell; its platform pre-script sources
# this file (passed as the suite's ACTIVATE_ENV template variable). After this
# returns, the task has: rose/cylc/psyclone + the Spack view on PATH, the MPI/IO
# compiler wrappers for the selected variant, and XIOS/HDF5/netCDF/shumlib
# locatable by the LFRic Makefiles (FFLAGS/LDFLAGS) — exactly what `build_*` and
# the `lfric_atm` run tasks need.
#
# It reads two variables from the task environment (the suite injects them via
# its [runtime][root][[environment]] block — see the suite's flow.cylc):
#   LFRIC_STACK   cray | spack   (which built variant to activate)
#   LFRIC_PREFIX  the prefix Stage 1 installed into (modulefile + view live here)
# Both fall back to the same defaults as Stage 1/2 (scripts/common.sh).
#
# SOURCE this file; do not execute it. Keep it side-effect-light (env + module
# loads only) — no Cylc config writing (that is run-suite.sh's job).

# Locate the repo: this file is at examples/science-suites/site/activate-env.sh.
_aenv_here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
_aenv_repo="${PIXI_PROJECT_ROOT:-$(cd -- "$_aenv_here/../../.." && pwd)}"

# common.sh sets PREFIX/MODULEFILES_DIR/MODULE_NAME/SPACK_ENV_DIR/LFRIC_STACK and
# puts vendored spack on PATH. It respects LFRIC_PREFIX/LFRIC_STACK from the task.
# BUT it also forces WORKING_DIR=$PREFIX/stage (Stage 1's transient Spack stage) —
# which would make the suite build reuse a stale shared stage dir (duplicate
# PSyclone kernels / sqlite module rows). A science-suite sets its own per-task
# WORKING_DIR ($BUILD_ROOT/<app>, node-local); preserve it across common.sh.
_save_wd="${WORKING_DIR:-}"
# shellcheck source=scripts/common.sh
. "$_aenv_repo/scripts/common.sh"
[ -n "$_save_wd" ] && export WORKING_DIR="$_save_wd"
unset _save_wd

_aenv_warn() { echo "WARN: activate-env.sh: $*" >&2; }

# --- Lmod: load the built environment (Stage 1) ----------------------------
# A clean suite-task shell may not have `module` initialised; source Lmod first.
if ! command -v module >/dev/null 2>&1; then
  for _f in /opt/cray/pe/lmod/lmod/init/bash /etc/profile.d/lmod.sh \
            /etc/profile.d/modules.sh /usr/share/lmod/lmod/init/bash; do
    # shellcheck source=/dev/null
    [ -f "$_f" ] && . "$_f" && break
  done
fi
# The modulefile sets APPS_ROOT_DIR/CORE_ROOT_DIR (→ our vendored trees) and
# LFRIC_TARGET_PLATFORM/FPP for the minimal-compile example's convenience. A
# science-suite OWNS these:
# it builds from its own extracted source trees ($SOURCE_ROOT/lfric_{apps,core},
# pinned to the suite's ref) and its own target/FPP. So preserve any value the
# suite already set in the task environment across the module load — otherwise the
# build mixes two source trees (duplicate kernels, version-skewed modules).
_save_apps="${APPS_ROOT_DIR:-}"; _save_core="${CORE_ROOT_DIR:-}"
_save_tp="${LFRIC_TARGET_PLATFORM:-}"; _save_fpp="${FPP:-}"
if command -v module >/dev/null 2>&1; then
  module use "$MODULEFILES_DIR"
  module load "$MODULE_NAME" || _aenv_warn "could not 'module load $MODULE_NAME'"
else
  _aenv_warn "no 'module' command — cannot load $MODULE_NAME (is Lmod available?)"
fi
[ -n "$_save_apps" ] && export APPS_ROOT_DIR="$_save_apps"
[ -n "$_save_core" ] && export CORE_ROOT_DIR="$_save_core"
[ -n "$_save_tp" ]   && export LFRIC_TARGET_PLATFORM="$_save_tp"
[ -n "$_save_fpp" ]  && export FPP="$_save_fpp"
unset _save_apps _save_core _save_tp _save_fpp

# --- HDF5 file locking on Lustre -------------------------------------------
# Isambard 3's cylc-run lives on Lustre. HDF5 1.10+ tries to flock() files it
# creates; Lustre rejects that, so XIOS's nc_create() of a NetCDF-4/HDF5 output
# (e.g. lfric_ver_tp0.nc) aborts with "Permission denied" *after* leaving a
# 0-byte file — the model integrates fine, it just can't write diagnostics.
# Disabling HDF5's own locking is the standard remedy and is safe here (Cylc
# already serialises task access to these paths). Honour any value already set.
export HDF5_USE_FILE_LOCKING="${HDF5_USE_FILE_LOCKING:-FALSE}"

# --- Spack env view: includes + libs for the LFRic Makefiles ----------------
# The modulefile puts $view/bin on PATH and shumlib on LDFLAGS, but the LFRic
# build also needs the view's headers (xios.mod, …) and libraries (libxios.a,
# yaxt, pFUnit, and — spack variant — HDF5/netCDF). Mirror examples/minimal-compile/
# build.sh: prepend the view's include/lib to FFLAGS/LDFLAGS (the Cray ftn wrapper
# ignores CPATH/LIBRARY_PATH, so these must go through F/LDFLAGS). Prepend, so a
# value the task already set is preserved.
_aenv_view="$SPACK_ENV_DIR/.spack-env/view"
if [ -d "$_aenv_view/include" ]; then
  export FFLAGS="-I$_aenv_view/include${FFLAGS:+ $FFLAGS}"
  export LDFLAGS="-L$_aenv_view/lib -L$_aenv_view/lib64 -Wl,-rpath=$_aenv_view/lib -Wl,-rpath=$_aenv_view/lib64${LDFLAGS:+ $LDFLAGS}"
  export LD_LIBRARY_PATH="$_aenv_view/lib:$_aenv_view/lib64${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
else
  _aenv_warn "Spack env view missing at $_aenv_view — is the '$LFRIC_STACK' variant built?"
fi

# --- Variant compiler / MPI-IO wrappers ------------------------------------
# Same contract as examples/minimal-compile/build.sh. The suite's BUILD task sets
# FC/LDMPI=mpif90 for isambard3 (the spack variant's native wrapper); for the
# cray variant we must OVERRIDE to the Cray ftn/CC wrappers and load PrgEnv-gnu +
# the Cray parallel HDF5/netCDF modules (those inject -I/-L/-l for HDF5/netCDF,
# which are Cray externals, not in the view).
if [ "$LFRIC_STACK" = cray ]; then
  PRGENV_MODULE="${PRGENV_MODULE:-PrgEnv-gnu}"
  CRAYPE_TARGET="${CRAYPE_TARGET:-craype-arm-grace}"
  HDF5_MODULE="${HDF5_MODULE:-cray-hdf5-parallel/1.14.3.9}"
  NETCDF_MODULE="${NETCDF_MODULE:-cray-netcdf-hdf5parallel/4.9.2.3}"
  if command -v module >/dev/null 2>&1; then
    module load "$PRGENV_MODULE" || _aenv_warn "could not 'module load $PRGENV_MODULE'"
    module load "$CRAYPE_TARGET" 2>/dev/null || true
    module load "$HDF5_MODULE" "$NETCDF_MODULE" \
      || _aenv_warn "could not load $HDF5_MODULE / $NETCDF_MODULE"
  fi
  # Override the suite's mpif90 defaults — the Cray PE has no mpif90.
  export FC=ftn
  export LDMPI=ftn
  export CXX=CC
  export FPP="${FPP:-cpp -traditional-cpp}"
else
  # spack variant: the view's mpich wrappers (mpif90 wraps gfortran-14, mpic++
  # wraps g++-14). Set only if the task did not already (it usually sets mpif90).
  _aenv_fc=""; for _c in mpif90 mpifort; do command -v "$_c" >/dev/null 2>&1 && { _aenv_fc="$_c"; break; }; done
  [ -n "$_aenv_fc" ] || _aenv_warn "no mpich Fortran wrapper (mpif90/mpifort) on PATH — is the spack variant built?"
  export FC="${FC:-$_aenv_fc}"
  export LDMPI="${LDMPI:-$_aenv_fc}"
  export CXX="${CXX:-mpic++}"
  export FPP="${FPP:-cpp -traditional-cpp}"
fi

unset _aenv_here _aenv_repo _aenv_view _aenv_fc _c _f
hash -r 2>/dev/null || true
