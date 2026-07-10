#!/usr/bin/env bash
# gen-modulefile.sh — write the per-variant Lmod modulefile for LFRIC_STACK.
#
# This replaces the old env-runtime-<variant>.sh shell snippet. The
# environment is loaded with `module load lfric-env/<cray|spack>` (and pixi auto-
# activation does the same via scripts/activate.sh).
#
# To keep the modulefile auditable, the LOGIC (what gets put on PATH/LD_*, the
# conditionals, pushenv composition, ordering) lives in the version-controlled,
# syntax-highlighted scripts/lfric-env.lua. THIS script only resolves the per-
# build paths and emits a flat Lua DATA table; the generated file then runs the
# committed logic with it:
#     local data = { ... }
#     assert(loadfile(".../scripts/lfric-env.lua"))(data)
# (Lmod's sandbox forbids dofile() but allows loadfile() + an argument.)
#
# Called by build.sh after `env view regenerate`, but also runnable on its own to
# regenerate the modulefile without a full rebuild (the env must already be
# concretized + installed; it uses the vendored `spack` CLI from common.sh). For
# the cray variant, run with the Cray PE modules loaded (PrgEnv-gnu + cray-hdf5/
# netcdf) so CRAY_LD_LIBRARY_PATH is populated.
set -uo pipefail

_here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=scripts/common.sh
. "$_here/common.sh"

info() { echo "INFO: $*"; }
warn() { echo "WARN: $*" >&2; }
die()  { echo "ERROR: $*" >&2; exit 1; }

case "$LFRIC_STACK" in
  cray|spack) ;;
  *) die "LFRIC_STACK must be 'cray' or 'spack' (got '$LFRIC_STACK')" ;;
esac

logic="$_here/lfric-env.lua"
view="$SPACK_ENV_DIR/.spack-env/view"
[ -f "$logic" ] || die "missing modulefile logic: $logic"
# Snapshot the committed logic next to the generated modulefiles, under PREFIX,
# and have the modulefile loadfile() THAT copy — not the in-repo original — so
# `module load` stays self-contained: the examples must not depend on the repo path
# (it may have moved/been deleted since the build). Byte-identical to the tracked
# scripts/lfric-env.lua, refreshed every build.
installed_logic="$MODULEFILES_DIR/lfric-env.lua"
[ -d "$view/bin" ] || die "Spack env view missing at $view — build it first: sbatch scripts/build.sbatch (or: pixi run build)"
command -v spack >/dev/null 2>&1 || die "spack CLI not on PATH (common.sh should add it)"

# --- Lua literal helpers (the only quoting this script does) ----------------
lua_q()  { local s=${1:-}; s=${s//\\/\\\\}; s=${s//\"/\\\"}; printf '"%s"' "$s"; }
lua_qn() { if [ -n "${1:-}" ]; then lua_q "$1"; else printf 'nil'; fi; }   # string or nil
lua_list() {                                                               # args -> { "a", "b" } (none -> {})
  local x out=""
  for x in "$@"; do
    [ -n "$out" ] && out+=", "
    out+="$(lua_q "$x")"
  done
  [ -n "$out" ] && printf '{ %s }' "$out" || printf '{}'
}

# --- Resolve the per-build, hash-addressed install prefixes -----------------
shumlib_prefix="$(spack -e "$SPACK_ENV_DIR" location -i shumlib 2>/dev/null || true)"
python_prefix="$(spack -e "$SPACK_ENV_DIR" location -i python 2>/dev/null || true)"
psyclone_prefix="$(spack -e "$SPACK_ENV_DIR" location -i py-psyclone 2>/dev/null || true)"
rose_picker_prefix="$(spack -e "$SPACK_ENV_DIR" location -i rose-picker 2>/dev/null || true)"

shumlib_lib=""
if [ -n "$shumlib_prefix" ]; then
  if [ -d "$shumlib_prefix/lib" ]; then
    shumlib_lib="$shumlib_prefix/lib"
  elif [ -d "$shumlib_prefix/lib64" ]; then
    shumlib_lib="$shumlib_prefix/lib64"
  fi
fi
psyclone_cfg=""
[ -n "$psyclone_prefix" ] && [ -f "$psyclone_prefix/share/psyclone/psyclone.cfg" ] \
  && psyclone_cfg="$psyclone_prefix/share/psyclone/psyclone.cfg"

# --- Compiler/MPI setup the modulefile needs to bake in ---------------------
# So `module load lfric-env/<version>/<variant>` alone is enough to compile and
# run against this environment (examples/minimal-compile/build.sh used to
# require the caller to separately module-load these and export FC/CXX/LDMPI —
# now lfric-env.lua does it). cray: the Cray PE module names (same version
# constants as scripts/lib.sh — must match the externals in
# spack-env/cray/spack.yaml). spack: the view's own MPI Fortran/C++ wrapper
# leaf names (lfric_core picks its per-compiler flag profile from the wrapper
# leaf name, so this must be mpif90 specifically if present, not mpifort).
prgenv_module=""; craype_target=""; hdf5_module=""; netcdf_module=""
mpi_fc=""; mpi_cxx=""
if [ "$LFRIC_STACK" = cray ]; then
  prgenv_module="${PRGENV_MODULE:-PrgEnv-gnu}"
  craype_target="${CRAYPE_TARGET:-craype-arm-grace}"
  hdf5_module="${HDF5_MODULE:-cray-hdf5-parallel/1.14.3.9}"
  netcdf_module="${NETCDF_MODULE:-cray-netcdf-hdf5parallel/4.9.2.3}"
else
  for _c in mpif90 mpifort; do
    [ -x "$view/bin/$_c" ] && { mpi_fc="$_c"; break; }
  done
  [ -x "$view/bin/mpic++" ] && mpi_cxx="mpic++"
  # Fail fast: without these the generated modulefile cannot set FC/CXX/LDMPI, so a
  # single `module load` would silently NOT satisfy the toolchain contract. A fully
  # built spack view always ships them; missing = a broken/incomplete build.
  [ -n "$mpi_fc" ]  || die "no mpif90/mpifort in $view/bin — the spack view's MPI Fortran wrapper is missing, so the modulefile cannot set FC/LDMPI. Is the '$LFRIC_STACK' env fully built?"
  [ -n "$mpi_cxx" ] || die "no mpic++ in $view/bin — the spack view's MPI C++ wrapper is missing, so the modulefile cannot set CXX. Is the '$LFRIC_STACK' env fully built?"
fi

# The view's python site-packages (usually one; glob in case of a version bump).
pythonpath=()
for _sp in "$view"/lib/python*/site-packages; do
  [ -d "$_sp" ] && pythonpath+=("$_sp")
done

# Cray MPI/IO runtime lib dirs (cray variant only), in final front-to-back order.
cray_libs=()
if [ "$LFRIC_STACK" = cray ]; then
  if [ -n "${CRAY_MPICH_DIR:-}" ]; then
    _OLDIFS=$IFS; IFS=:
    for _d in $CRAY_MPICH_DIR/lib${CRAY_LD_LIBRARY_PATH:+:$CRAY_LD_LIBRARY_PATH}; do
      [ -n "$_d" ] && cray_libs+=("$_d")
    done
    IFS=$_OLDIFS
  else
    warn "CRAY_MPICH_DIR unset — modulefile will lack the Cray MPI lib paths."
    warn "Re-run with the Cray PE modules loaded (PrgEnv-gnu + cray-hdf5/netcdf)."
  fi
fi

pythonpath_lua='{}'; [ ${#pythonpath[@]} -gt 0 ] && pythonpath_lua="$(lua_list "${pythonpath[@]}")"
cray_libs_lua='{}';  [ ${#cray_libs[@]}  -gt 0 ] && cray_libs_lua="$(lua_list "${cray_libs[@]}")"

# --- Emit the data table + a call into the committed logic ------------------
mkdir -p "$(dirname "$MODULEFILE")"
# Place the logic snapshot under PREFIX (shared by both variants) so the emitted
# loadfile() path is repo-independent.
cp -f "$logic" "$installed_logic" || die "failed to snapshot logic to $installed_logic"
info "Writing Lmod modulefile ($MODULEFILE)"

# Cray module prerequisites (cray variant only) — MUST be literal load()/
# try_load() calls at the TOP LEVEL of this generated file, not inside the
# shared scripts/lfric-env.lua reached via loadfile(): Lmod resolves module
# hierarchy (MODULEPATH changes from loading a compiler family) by statically
# scanning the top-level modulefile source for load(...) calls, so a load()
# only reachable via loadfile() is invisible to that scan and silently does
# nothing (verified on this system: try_load() still works when nested, but
# the required load() calls do not — so keep all of them here for safety).
cray_loads=""
if [ "$LFRIC_STACK" = cray ]; then
  cray_loads="load($(lua_q "$prgenv_module"))
try_load($(lua_q "$craype_target"))
load($(lua_q "$hdf5_module"))
load($(lua_q "$netcdf_module"))
"
fi

cat > "$MODULEFILE" <<EOF
-- Generated by gen-modulefile.sh on $(date -u '+%Y-%m-%dT%H:%M:%SZ'). Do not edit.
-- Per-build path data for the $LFRIC_STACK variant; the logic that consumes it is
-- version-controlled (and audited) in scripts/lfric-env.lua.
${cray_loads}local data = {
  variant         = $(lua_q  "$LFRIC_STACK"),
  repo_root       = $(lua_q  "$REPO_ROOT"),
  -- Absolute paths to the (relocated, under-PREFIX) Spack env + its view, so the
  -- modulefile does not derive them from repo_root: the examples stay repo-independent.
  spack_env       = $(lua_q  "$SPACK_ENV_DIR"),
  view            = $(lua_q  "$SPACK_ENV_DIR/.spack-env/view"),
  shumlib         = $(lua_qn "$shumlib_prefix"),
  shumlib_lib     = $(lua_qn "$shumlib_lib"),
  python          = $(lua_qn "$python_prefix"),
  psyclone        = $(lua_qn "$psyclone_prefix"),
  psyclone_cfg    = $(lua_qn "$psyclone_cfg"),
  rose_picker     = $(lua_qn "$rose_picker_prefix"),
  pythonpath      = $pythonpath_lua,
  cray_libs       = $cray_libs_lua,
  target_platform = $(lua_q  "${LFRIC_TARGET_PLATFORM:-meto-spice}"),
  fpp             = $(lua_q  "${FPP:-cpp -traditional-cpp}"),
  -- Compiler/MPI setup (cray: Cray PE module names; spack: view MPI wrapper
  -- leaf names) — see the block above that computes these.
  prgenv_module   = $(lua_qn "$prgenv_module"),
  craype_target   = $(lua_qn "$craype_target"),
  hdf5_module     = $(lua_qn "$hdf5_module"),
  netcdf_module   = $(lua_qn "$netcdf_module"),
  mpi_fc          = $(lua_qn "$mpi_fc"),
  mpi_cxx         = $(lua_qn "$mpi_cxx"),
}
assert(loadfile($(lua_q "$installed_logic")))(data)
EOF

# Default selectors so a bare `module load` picks a sensible target (cray is the
# project default variant; the most-recently-built version becomes the bare-
# `lfric-env` default). Modulefiles are now keyed lfric-env/<version>/<variant>:
#   - per-version .modulerc: within this version, default variant = cray, so
#     `module load lfric-env/<version>` resolves to cray.
#   - top-level .modulerc: bare `module load lfric-env` resolves to this version's
#     cray (rewritten each build, so the newest build wins).
# Both are idempotent (rewritten each build). The build/smoke path loads the full
# MODULE_NAME explicitly, so these only affect human-convenience bare loads.
mkdir -p "$MODULEFILES_DIR/lfric-env/$LFRIC_ENV_VERSION"
cat > "$MODULEFILES_DIR/lfric-env/$LFRIC_ENV_VERSION/.modulerc.lua" <<EOF
-- Generated by gen-modulefile.sh. Within $LFRIC_ENV_VERSION, default variant = cray.
module_version("lfric-env/$LFRIC_ENV_VERSION/cray", "default")
EOF
cat > "$MODULEFILES_DIR/lfric-env/.modulerc.lua" <<EOF
-- Generated by gen-modulefile.sh. Bare 'module load lfric-env' default =
-- the most recently built version's cray variant.
module_version("lfric-env/$LFRIC_ENV_VERSION/cray", "default")
EOF

info "Modulefile written. Load it with:"
info "  module use $MODULEFILES_DIR && module load $MODULE_NAME"
