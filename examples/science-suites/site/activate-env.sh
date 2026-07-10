#!/usr/bin/env bash
# examples/science-suites/site/activate-env.sh — the ACTIVATE_ENV a science-suite
# task SOURCES to put our built environment on the toolchain. It is the
# analogue of the upstream env_lfric/activate.sh, but built on OUR Lmod modulefile
# (Stage 1) rather than a raw `spack env activate`.
#
# A Cylc/Rose suite task runs in a clean shell; its platform pre-script sources
# this file (passed as the suite's ACTIVATE_ENV template variable). After this
# returns, the task has rose/cylc/psyclone + the Spack view on PATH, the MPI/IO
# compiler wrappers for the selected variant (FC/CXX/LDMPI), and XIOS/HDF5/netCDF/
# shumlib locatable by the LFRic Makefiles (FFLAGS/LDFLAGS) — exactly what
# `build_*` and the `lfric_atm` run tasks need.
#
# Crucially, ALL of that toolchain setup is supplied by the `module load` alone:
# this file is a THIN activator, like an end user's. It no longer hand-rolls the
# Cray module loads / FC-CXX-LDMPI exports / view FFLAGS-LDFLAGS (that moved into
# the modulefile — scripts/lfric-env.lua); it only initialises Lmod, loads the
# module (preserving the vars a suite OWNS — see below), and adds the one thing
# the module cannot: the Lustre HDF5 file-locking workaround. The suite inherits
# the compiler from the module via `FC = $FC` in its flow.cylc (see README.md).
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

# --- Toolchain / FFLAGS / LDFLAGS: all from the loaded module ----------------
# The lfric-env module loaded above supplies the COMPLETE compile toolchain for
# the selected variant — FC/CXX/LDMPI (cray: ftn/CC; spack: the view's mpif90/
# mpic++), the Cray PE modules (cray variant), and the view's FFLAGS/LDFLAGS
# (XIOS/HDF5/netCDF/shumlib .mod files + libs). So this file no longer sets any
# of it. It used to OVERRIDE the suite's FC=mpif90 to ftn for cray and re-derive
# the view flags — exactly the coupling to Stage-1 internals we removed. The
# suite now inherits the compiler from the module (its flow.cylc [[BUILD]] does
# `FC = $FC` / `LDMPI = $LDMPI`), which is the end-user pattern in README.md.

unset _aenv_here _aenv_repo _f
hash -r 2>/dev/null || true
