#!/usr/bin/env bash
# build.sh — build the LFRic Apps Spack environment.
#
# This is the bulk of the original walkthrough.sh / install.sh: it produces a
# complete, activatable Spack environment (rose, cylc, psyclone, xios, mpich,
# ...). It does NOT compile lfric_atm — that needs the private physics repos
# (casim/jules/socrates/ukca) and is the Stage-2 example in examples/lfric-atm/.
#
# All heavy output goes under PREFIX (outside the repo). Re-runs are cheap:
# Spack skips already-built, content-addressed packages.
set -uo pipefail

_here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=scripts/common.sh
. "$_here/common.sh"

SPACK_JOBS="${SPACK_JOBS:-8}"
# A few packages have translation units that use several GB each: node-js/rust
# bundle LLVM/V8, and xios' group_template_decl.cpp is a heavy C++ template unit.
# At high -j on a memory-capped job they OOM (cc1plus gets SIGKILLed — "Killed
# signal terminated program cc1plus"). Build those at a capped -j (HEAVY_JOBS)
# before the rest. HEAVY_PKGS lists them. (The sbatch scripts also request enough
# memory via --mem; this cap is the in-build belt-and-suspenders for either path.)
HEAVY_JOBS="${HEAVY_JOBS:-${NODE_JS_JOBS:-6}}"
HEAVY_PKGS=(${HEAVY_PKGS:-node-js rust xios})
COMPILER_SPEC="${COMPILER_SPEC:-gcc@14.3.0}"
COMPILER_SPEC="${COMPILER_SPEC#%}"
# Cray PrgEnv-gnu provides the compiler (gcc-native/14 == /usr/bin/gcc-14 ==
# gcc@14.3.0) AND the cray-mpich/libfabric/cray-pmi used as externals.
# craype-arm-grace selects the Neoverse-V2 (Grace) CPU target.
PRGENV_MODULE="${PRGENV_MODULE:-PrgEnv-gnu}"
CRAYPE_TARGET="${CRAYPE_TARGET:-craype-arm-grace}"
# Cray parallel HDF5 + netCDF-C/Fortran modules (cray variant only), backing the
# externals in spack-env/cray/spack.yaml. Not part of the default PrgEnv-gnu:
# they live under the cray-mpich module hierarchy (load AFTER PrgEnv-gnu) and
# default to an older version — so pin them. Versions must match the external
# prefixes in spack-env/cray/spack.yaml.
HDF5_MODULE="${HDF5_MODULE:-cray-hdf5-parallel/1.14.3.9}"
NETCDF_MODULE="${NETCDF_MODULE:-cray-netcdf-hdf5parallel/4.9.2.3}"

info() { echo "INFO: $*"; }
warn() { echo "WARN: $*" >&2; }
die()  { echo "ERROR: $*" >&2; exit 1; }

# Dependency stack variant (cray | spack), set in common.sh. Validate here (an
# executed script, where die is safe) and report which environment we build.
case "$LFRIC_STACK" in
  cray|spack) ;;
  *) die "LFRIC_STACK must be 'cray' or 'spack' (got '$LFRIC_STACK')" ;;
esac
info "Dependency stack variant: LFRIC_STACK=$LFRIC_STACK (env: $SPACK_ENV_DIR)"

# --- Python preflight (this Python RUNS Spack) -----------------------------
# pixi is optional for the build; the one thing it otherwise provides is a
# suitable Python. Spack 1.0 needs CPython >=3.7 and <3.12 (it parses sources
# with ast.Str, removed in 3.12; some deps want >=3.8). common.sh points
# SPACK_PYTHON at `python3`: under pixi that is the pinned 3.11, without pixi it
# is whatever you brought (on Isambard: `module load cray-python/3.11.7`). Check
# it here so a missing/too-new Python fails with a clear hint instead of a deep
# Spack traceback later.
_py="${SPACK_PYTHON:-$(command -v python3 2>/dev/null || true)}"
[ -n "$_py" ] && [ -x "$_py" ] \
  || die "no Python found to run Spack. Load one ('module load cray-python/3.11.7', or any python3 in [3.7,3.12)) and re-run — or use pixi ('pixi run build')."
_pyver="$("$_py" -c 'import sys; print("%d.%d" % sys.version_info[:2])' 2>/dev/null || true)"
case "$_pyver" in
  3.7|3.8|3.9|3.10|3.11) info "Spack Python: $_py ($_pyver)" ;;
  *) die "Spack needs Python >=3.7 and <3.12 (found '${_pyver:-unknown}' at $_py). Load a suitable one ('module load cray-python/3.11.7') and re-run — or use pixi ('pixi run build')." ;;
esac

mkdir -p "$PREFIX" "$SPACK_USER_CONFIG_PATH" "$SPACK_USER_CACHE_PATH"

# --- 0. Submodules present? ------------------------------------------------
for sub in spack spack-packages lfric_apps lfric_core mo-spack-packages; do
  git -C "$REPO_ROOT/vendor/$sub" rev-parse --git-dir >/dev/null 2>&1 \
    || die "Submodule vendor/$sub is missing. Run: git submodule update --init --recursive --jobs 4 -- vendor/spack vendor/spack-packages vendor/lfric_apps vendor/lfric_core vendor/mo-spack-packages  (or: pixi run submodule-init)"
done

# --- 1. Apply patches (idempotent; build is self-contained) ----------------
info "Applying patches"
bash "$_here/patch-all.sh" || die "patch-all failed"

# --- 2. Toolchain + MPI/IO stack -------------------------------------------
# The compiler is gcc@14.3.0 (== gcc-native/14 == /usr/bin/gcc-14), an explicit
# external in spack-env/common.yaml, for BOTH variants. LFRIC_STACK decides the
# MPI + parallel I/O provider:
#   cray  - system cray-mpich + Cray parallel HDF5/netCDF (externals). Loading
#           PrgEnv-gnu is REQUIRED (not a nicety): it puts cray-mpich/libfabric/
#           cray-pmi on the module path so their externals resolve, and sets the
#           CRAY_* lib paths needed at build/link time. craype-arm-grace selects
#           the Neoverse-V2 (Grace) target. cray-hdf5-parallel/cray-netcdf-
#           hdf5parallel back the hdf5/netcdf externals: loading them puts the
#           same (parallel, gnu/12.3) lib dirs on CRAY_LD_LIBRARY_PATH, which the
#           runtime snippet captures so view binaries resolve their .so at run.
#   spack - mpich + HDF5/netCDF built from source; no Cray modules are loaded
#           (the gcc external is the always-present system /usr/bin/gcc-14).
if [ "$LFRIC_STACK" = cray ]; then
  if ! command -v module >/dev/null 2>&1; then
    for f in /opt/cray/pe/lmod/lmod/init/bash /etc/profile.d/lmod.sh \
             /etc/profile.d/modules.sh /usr/share/lmod/lmod/init/bash; do
      # shellcheck source=/dev/null
      [ -f "$f" ] && . "$f" && break
    done
  fi
  command -v module >/dev/null 2>&1 \
    || die "no 'module' command found — cannot load $PRGENV_MODULE; cray-mpich external will not resolve"
  module load "$PRGENV_MODULE" || die "could not 'module load $PRGENV_MODULE'"
  module load "$CRAYPE_TARGET" 2>/dev/null \
    || warn "could not load $CRAYPE_TARGET (target may default to aarch64)"
  module load "$HDF5_MODULE" "$NETCDF_MODULE" \
    || die "could not load $HDF5_MODULE / $NETCDF_MODULE (parallel Cray HDF5/netCDF backing the cray/spack.yaml externals)"
  if [ -n "${CRAY_MPICH_DIR:-}" ] && [ -d "${CRAY_MPICH_DIR:-/nonexistent}" ]; then
    info "cray-mpich: $CRAY_MPICH_DIR (v${CRAY_MPICH_VERSION:-?})"
  else
    die "CRAY_MPICH_DIR unset/missing after 'module load $PRGENV_MODULE' — cray-mpich external cannot resolve"
  fi
else
  info "LFRIC_STACK=spack: building mpich + HDF5/netCDF from source; loading no Cray modules"
fi
GCC_FC="${GCC_FC:-/usr/bin/gfortran-14}"
if [ -x "$GCC_FC" ]; then
  info "gcc (external): $("$GCC_FC" --version 2>/dev/null | head -1)"
else
  warn "$GCC_FC missing — the env's gcc external (common.yaml) may not build Fortran"
fi

# --- 3. XIOS source verification (non-fatal) -------------------------------
if [ "${RUN_XIOS_VERIFICATION:-1}" = "1" ]; then
  info "Verifying XIOS source (set RUN_XIOS_VERIFICATION=0 to skip)"
  XIOS_WORKDIR="$PREFIX/xios-verification" bash "$_here/xios-verification.sh" \
    || warn "XIOS verification failed; continuing (the xios Spack package pins the same commit)"
fi

# --- 4. Bootstrap Spack ----------------------------------------------------
[ -f "$SPACK_ROOT/share/spack/setup-env.sh" ] || die "vendored spack missing setup-env.sh"
# shellcheck source=/dev/null
. "$SPACK_ROOT/share/spack/setup-env.sh"
spack --version || die "spack unavailable after sourcing setup-env.sh"

# --- 5. Install tree + caches ----------------------------------------------
# Without install_tree, Spack would install into vendor/spack/opt (inside the
# submodule). The install tree + caches go under PREFIX (persistent, so built
# packages + downloaded tarballs survive a re-run).
#
# WORKING_DIR is Spack's transient build/compile stage. It is metadata-heavy
# (autotools/libtool touch thousands of small files), so on a compute node it
# should be node-local NVMe: the sbatch sets LFRIC_WORKING_DIR=$LOCALDIR/... to
# keep the install phase off the shared (often contended) Lustre. It defaults to
# $PREFIX/stage (on Lustre: correct, just slower). See MAINTAINER.md.
BUILD_STAGE="$WORKING_DIR"
mkdir -p "$BUILD_STAGE" || die "build stage not writable: $BUILD_STAGE (set LFRIC_WORKING_DIR)"
info "Install prefix (persistent):   $PREFIX"
info "Build stage    (transient):    $BUILD_STAGE"
cat > "$SPACK_USER_CONFIG_PATH/config.yaml" <<EOF
config:
  install_tree:
    root: $PREFIX/opt
  build_stage:
  - $BUILD_STAGE
  source_cache: $PREFIX/source-cache
  misc_cache: $PREFIX/misc-cache
  build_jobs: $SPACK_JOBS
EOF

# --- 6. Compilers ----------------------------------------------------------
# The compiler is declared as an explicit external in spack-env/common.yaml
# (gcc@14.3.0) and pinned via per-language requires, so we deliberately do NOT
# run `spack compiler find`: with the env active (pixi activates it) that would
# rewrite the tracked manifest, and a stray gcc on PATH could derail the solve.
info "Using gcc external pinned in spack.yaml ($COMPILER_SPEC)"

# --- 6b. Instantiate the directory environment under PREFIX ----------------
# The Spack environment is built OUTSIDE the repo so its view + lockfile land
# under PREFIX, making Stage 2 (module load) independent of the repo's location.
# We generate $SPACK_ENV_DIR/spack.yaml from the tracked template, rewriting its
# relative `include: ../common.yaml` to an absolute path back into the repo (so
# the shared, version-controlled config is still used). See MAINTAINER.md.
[ -f "$SPACK_ENV_TEMPLATE" ] || die "missing env template: $SPACK_ENV_TEMPLATE"
mkdir -p "$SPACK_ENV_DIR"
# Literal (non-regex) replacement of the relative include with the absolute path,
# done in awk via index()/substr so nothing in $REPO_ROOT is interpreted — sed's
# replacement would mangle a '&', backslash or the delimiter if a path ever
# contained one. The path is passed through the environment (ENVIRON), which awk
# does not run C-escape processing on (unlike -v), so even a backslash is safe.
LFRIC_COMMON_YAML="$REPO_ROOT/spack-env/common.yaml" \
  awk '
    { i = index($0, "../common.yaml")
      if (i > 0) $0 = substr($0, 1, i-1) ENVIRON["LFRIC_COMMON_YAML"] substr($0, i + length("../common.yaml"))
      print }
  ' "$SPACK_ENV_TEMPLATE" > "$SPACK_ENV_DIR/spack.yaml" \
  || die "failed to generate $SPACK_ENV_DIR/spack.yaml from template"
grep -q "$REPO_ROOT/spack-env/common.yaml" "$SPACK_ENV_DIR/spack.yaml" \
  || die "include rewrite produced no absolute common.yaml path in $SPACK_ENV_DIR/spack.yaml"
info "Spack env instantiated at $SPACK_ENV_DIR (from $SPACK_ENV_TEMPLATE)"

# --- 7. Sanity: environment repos resolve (incl. vendored builtin) ---------
info "Environment package repos:"
spack -e "$SPACK_ENV_DIR" repo list || die "spack repo list failed (check spack-env/common.yaml repo paths)"

# --- 8. Concretize ---------------------------------------------------------
# --fresh: this is a pinned, reproducible env (submodule-pinned spack +
# spack-packages), so a fresh solve is deterministic and avoids reusing stale
# specs from an earlier (self-built-mpich) install tree. `install` still skips
# already-built identical hashes, so a fresh solve is not wasteful.
info "Concretizing $ENV_NAME"
spack -e "$SPACK_ENV_DIR" concretize -f --fresh || die "concretize failed"

# Assert the solve matches the requested variant, so a silently mis-resolved
# external (or a leaking PrgEnv) can never produce the wrong stack.
if [ "$LFRIC_STACK" = cray ]; then
  # MPI must be the system cray-mpich (providers in cray/spack.yaml). Fail loudly
  # if a from-source mpich/openmpi entered the DAG (e.g. the external stopped
  # resolving): that defeats the cray-mpich switch and risks a gfortran .mod
  # mismatch against our gcc@14.3.0.
  if grep -qE '"name":[[:space:]]*"(mpich|openmpi)"' "$SPACK_ENV_DIR/spack.lock" 2>/dev/null; then
    die "a from-source MPI (mpich/openmpi) entered the solve; expected only cray-mpich. Is PrgEnv-gnu loaded and the cray-mpich external resolving?"
  fi
  info "MPI provider: cray-mpich (external) — OK"
  # Likewise assert the Cray parallel HDF5/netCDF externals resolved: their
  # prefixes must appear in the solve. If an external stopped resolving, Spack
  # would silently build hdf5/netcdf-c from source — defeating the system-library
  # switch and risking a gfortran .mod mismatch against gcc@14.3.0.
  for _ext in /opt/cray/pe/hdf5-parallel /opt/cray/pe/netcdf-hdf5parallel; do
    grep -q "$_ext" "$SPACK_ENV_DIR/spack.lock" 2>/dev/null \
      || die "expected external prefix $_ext in the solve; hdf5/netcdf may have gone from-source. Are cray-hdf5-parallel/cray-netcdf-hdf5parallel loaded and the cray/spack.yaml externals resolving?"
  done
  info "HDF5/netCDF provider: cray-hdf5-parallel + cray-netcdf-hdf5parallel (external) — OK"
else
  # spack variant: the inverse — ensure we did NOT silently pick up the Cray
  # externals (e.g. a stray PrgEnv in the environment), so this really is the
  # from-source stack it claims to be.
  if grep -qE '"name":[[:space:]]*"cray-mpich"' "$SPACK_ENV_DIR/spack.lock" 2>/dev/null; then
    die "cray-mpich entered the LFRIC_STACK=spack solve; expected a from-source mpich. Is a Cray PrgEnv leaking into the environment?"
  fi
  if ! grep -qE '"name":[[:space:]]*"mpich"' "$SPACK_ENV_DIR/spack.lock" 2>/dev/null; then
    die "no from-source mpich in the LFRIC_STACK=spack solve (MPI provider did not resolve to mpich)."
  fi
  if grep -qE '/opt/cray/pe/(hdf5-parallel|netcdf-hdf5parallel)' "$SPACK_ENV_DIR/spack.lock" 2>/dev/null; then
    die "a Cray HDF5/netCDF external prefix entered the LFRIC_STACK=spack solve; expected from-source hdf5/netcdf."
  fi
  info "MPI/IO provider: from-source mpich + hdf5/netcdf — OK"
fi

if [ "${STOP_AFTER_CONCRETIZE:-0}" = "1" ]; then
  info "STOP_AFTER_CONCRETIZE=1 — concretization succeeded; stopping before install."
  echo "CONCRETIZE_OK"
  exit 0
fi

# --- 9. Install ------------------------------------------------------------
# libxml2 first (some netcdf-c builds probe xml2-config), then yaxt serially
# (known parallel race), then node-js, then the whole environment.
info "Installing libxml2 (serial pre-step)"
spack -e "$SPACK_ENV_DIR" install -j "$SPACK_JOBS" libxml2 || die "install libxml2 failed"
if libxml2_prefix="$(spack -e "$SPACK_ENV_DIR" location -i libxml2 2>/dev/null)"; then
  export XML2_CONFIG="$libxml2_prefix/bin/xml2-config"
  export PATH="$libxml2_prefix/bin:$PATH"
fi

info "Installing yaxt (serial; avoids a parallel race)"
spack -e "$SPACK_ENV_DIR" install -j 1 yaxt || die "install yaxt failed"

for hp in "${HEAVY_PKGS[@]}"; do
  if spack -e "$SPACK_ENV_DIR" find "$hp" >/dev/null 2>&1; then
    continue   # already installed
  fi
  # Only pre-build heavy pkgs that are actually in the concretized environment.
  # (node-js/rust used to be pulled in by cylc-uiserver, which the Spack 1.0 port
  # dropped, so they are no longer present — skip rather than fail.)
  if ! grep -q "\"name\": \"$hp\"" "$SPACK_ENV_DIR/spack.lock" 2>/dev/null; then
    info "$hp not in the concretized environment; skipping heavy pre-build"
    continue
  fi
  info "Installing $hp (-j $HEAVY_JOBS; bundles LLVM/V8 — capped to avoid OOM)"
  spack -e "$SPACK_ENV_DIR" install -j "$HEAVY_JOBS" "$hp" || die "install $hp failed"
done

info "Installing the full environment (-j $SPACK_JOBS)"
spack -e "$SPACK_ENV_DIR" install -j "$SPACK_JOBS" || die "install (full environment) failed"

# --- 10. View --------------------------------------------------------------
if ! spack -e "$SPACK_ENV_DIR" env view regenerate; then
  rm -rf "$SPACK_ENV_DIR/.spack-env/._view"
  spack -e "$SPACK_ENV_DIR" env view regenerate || die "view regenerate failed"
fi

# --- 11. Resolve runtime env once -> Lmod modulefile (per variant) ---------
# gen-modulefile.sh resolves the per-build view + package prefixes into a flat
# Lua data table ($PREFIX/modulefiles/lfric-env/<variant>.lua) that `module
# load` runs through the version-controlled logic in scripts/lfric-env.lua. It
# runs here (after the view exists) but is standalone, so the modulefile can be
# regenerated without a full rebuild. The CRAY_* lib paths it bakes in come from
# the Cray PE modules loaded in step 2.
bash "$_here/gen-modulefile.sh" || die "gen-modulefile.sh failed"

# --- 12. Smoke test --------------------------------------------------------
# shellcheck source=/dev/null
. "$_here/activate.sh"
info "rose:     $(rose --version 2>&1 || echo MISSING)"
info "cylc:     $(cylc --version 2>&1 || echo MISSING)"
info "psyclone: $(psyclone --version 2>&1 || echo MISSING)"

echo ""
echo "BUILD_OK — environment built ($LFRIC_STACK variant)."
echo "Use it (Stage 2):  module use $MODULEFILES_DIR && module load $MODULE_NAME"
echo "                   (inside pixi: any 'pixi run ...' auto-loads it)"
