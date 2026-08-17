#!/usr/bin/env bash
# gen-modulefile.sh — write the Lmod modulefile. This is Stage 1's product.
#
# The modulefile is deliberately in two halves:
#
#   lfric-env.lua      the LOGIC — what goes on PATH, which variables are set,
#                      in what order. Version-controlled, reviewable, identical
#                      for every build. Snapshotted next to the modulefiles at
#                      build time, and loaded from THERE, so `module load` never
#                      needs this repo on disk.
#   <version>/<variant>.lua   the DATA — the hash-addressed paths this
#                      particular build resolved to. Generated here, nothing else.
#
# So reviewing what `module load` does means reading one committed Lua file, not
# reverse-engineering a generated one.
#
# build.sh calls this after the view is linked. You can also run it on its own
# (`pixi run modulefile`) to regenerate against an already-installed environment
# — for the cray variant, only with the Cray PE modules loaded, since it reads
# CRAY_LD_LIBRARY_PATH.
set -uo pipefail
# Re-source the configuration in this process, so an inline override such as
# `LFRIC_STACK=spack bash build.sh` re-derives every path that depends on it.
cd -- "$(dirname -- "${BASH_SOURCE[0]}")" || exit 1
. ./env.sh || exit 1
. ./lib.sh

logic="$STAGE1_DIR/lfric-env.lua"
view="$SPACK_ENV_DIR/.spack-env/view"
installed_logic="$MODULEFILES_DIR/lfric-env.lua"

[ -f "$logic" ] || die "missing $logic"
[ -d "$view/bin" ] || die "no Spack view at $view — build the environment first (sbatch build.sbatch)"
command -v spack >/dev/null 2>&1 || die "spack not on PATH"

# --- Lua literal helpers (the only quoting this script does) ---------------
lua_q()  { local s=${1:-}; s=${s//\\/\\\\}; s=${s//\"/\\\"}; printf '"%s"' "$s"; }
lua_qn() { if [ -n "${1:-}" ]; then lua_q "$1"; else printf 'nil'; fi; }
lua_list() {
  local x out=""
  for x in "$@"; do [ -n "$out" ] && out+=", "; out+="$(lua_q "$x")"; done
  [ -n "$out" ] && printf '{ %s }' "$out" || printf '{}'
}

# --- Resolve this build's hash-addressed prefixes --------------------------
shumlib_prefix="$(spack -e "$SPACK_ENV_DIR" location -i shumlib 2>/dev/null || true)"
python_prefix="$(spack -e "$SPACK_ENV_DIR" location -i python 2>/dev/null || true)"
psyclone_prefix="$(spack -e "$SPACK_ENV_DIR" location -i py-psyclone 2>/dev/null || true)"
rose_picker_prefix="$(spack -e "$SPACK_ENV_DIR" location -i rose-picker 2>/dev/null || true)"

shumlib_lib=""
for d in "$shumlib_prefix/lib" "$shumlib_prefix/lib64"; do
  [ -n "$shumlib_prefix" ] && [ -d "$d" ] && { shumlib_lib="$d"; break; }
done
psyclone_cfg=""
[ -n "$psyclone_prefix" ] && [ -f "$psyclone_prefix/share/psyclone/psyclone.cfg" ] \
  && psyclone_cfg="$psyclone_prefix/share/psyclone/psyclone.cfg"

# The view's python site-packages (normally one; globbed against a version bump).
pythonpath=()
for sp in "$view"/lib/python*/site-packages; do [ -d "$sp" ] && pythonpath+=("$sp"); done

# --- The compiler the module will hand out ---------------------------------
# cray: the Cray wrappers (ftn/CC), which need their PE modules loaded — so the
#       generated file load()s them (see the note at the emit step below).
# spack: the view's own MPI wrappers. LFRic picks its per-compiler flag profile
#       from the wrapper's LEAF NAME (fortran/<fc>.mk, cxx/<cxx>.mk), and it
#       ships mpif90.mk and mpic++.mk — not mpifort.mk or mpicxx.mk. So these
#       names are load-bearing, not cosmetic.
mpi_fc=""; mpi_cxx=""
if [ "$LFRIC_STACK" != cray ]; then
  for c in mpif90 mpifort; do [ -x "$view/bin/$c" ] && { mpi_fc="$c"; break; }; done
  [ -x "$view/bin/mpic++" ] && mpi_cxx="mpic++"
  [ -n "$mpi_fc" ]  || die "no mpif90/mpifort in $view/bin — is the '$LFRIC_STACK' env fully built?"
  [ -n "$mpi_cxx" ] || die "no mpic++ in $view/bin — is the '$LFRIC_STACK' env fully built?"
fi

# Cray MPI/IO runtime library directories, in final front-to-back order.
cray_libs=()
if [ "$LFRIC_STACK" = cray ]; then
  [ -n "${CRAY_MPICH_DIR:-}" ] \
    || die "CRAY_MPICH_DIR unset — re-run with the Cray PE modules loaded (PrgEnv-gnu + cray-hdf5-parallel + cray-netcdf-hdf5parallel)"
  _OLDIFS=$IFS; IFS=:
  for d in $CRAY_MPICH_DIR/lib${CRAY_LD_LIBRARY_PATH:+:$CRAY_LD_LIBRARY_PATH}; do
    [ -n "$d" ] && cray_libs+=("$d")
  done
  IFS=$_OLDIFS
fi

pythonpath_lua='{}'; [ ${#pythonpath[@]} -gt 0 ] && pythonpath_lua="$(lua_list "${pythonpath[@]}")"
cray_libs_lua='{}';  [ ${#cray_libs[@]}  -gt 0 ] && cray_libs_lua="$(lua_list "${cray_libs[@]}")"

# --- Emit ------------------------------------------------------------------
mkdir -p "$(dirname "$MODULEFILE")" "$MODULEFILES_DIR"
cp -f "$logic" "$installed_logic" || die "failed to snapshot the logic to $installed_logic"

# The Cray module loads MUST be literal load()/try_load() calls at the top level
# of this generated file — not inside lfric-env.lua. Lmod resolves module
# hierarchy (the MODULEPATH changes a compiler family brings) by statically
# scanning the top-level modulefile source for load(...) calls; a load() reached
# only through loadfile() is invisible to that scan and silently does nothing.
# (Verified on this system: try_load() still works when nested, load() does not.)
cray_loads=""
if [ "$LFRIC_STACK" = cray ]; then
  cray_loads="load($(lua_q "$PRGENV_MODULE"))
try_load($(lua_q "$CRAYPE_TARGET"))
load($(lua_q "$HDF5_MODULE"))
load($(lua_q "$NETCDF_MODULE"))
"
fi

info "Writing $MODULEFILE"
cat > "$MODULEFILE" <<EOF
-- Generated by stage1/gen-modulefile.sh on $(date -u '+%Y-%m-%dT%H:%M:%SZ'). Do not edit.
-- Path data for the $LFRIC_ENV_VERSION / $LFRIC_STACK build. The logic that consumes it is
-- version-controlled in stage1/lfric-env.lua and snapshotted alongside this file.
${cray_loads}local data = {
  variant         = $(lua_q  "$LFRIC_STACK"),
  version         = $(lua_q  "$LFRIC_ENV_VERSION"),
  spack_env       = $(lua_q  "$SPACK_ENV_DIR"),
  view            = $(lua_q  "$view"),
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
  mpi_fc          = $(lua_qn "$mpi_fc"),
  mpi_cxx         = $(lua_qn "$mpi_cxx"),
}
assert(loadfile($(lua_q "$installed_logic")))(data)
EOF

# Default selectors, so shorter names resolve to something sensible:
#   module load lfric-env/<version>   -> that version's cray variant
#   module load lfric-env             -> the most recently built version, cray
# Both are rewritten every build; the explicit full name is what scripts use.
mkdir -p "$MODULEFILES_DIR/lfric-env/$LFRIC_ENV_VERSION"
printf -- '-- Generated by stage1/gen-modulefile.sh.\nmodule_version("lfric-env/%s/cray", "default")\n' \
  "$LFRIC_ENV_VERSION" > "$MODULEFILES_DIR/lfric-env/$LFRIC_ENV_VERSION/.modulerc.lua"
printf -- '-- Generated by stage1/gen-modulefile.sh. Bare "lfric-env" = newest build, cray variant.\nmodule_version("lfric-env/%s/cray", "default")\n' \
  "$LFRIC_ENV_VERSION" > "$MODULEFILES_DIR/lfric-env/.modulerc.lua"

info "Load it with:  module use $MODULEFILES_DIR && module load $MODULE_NAME"
