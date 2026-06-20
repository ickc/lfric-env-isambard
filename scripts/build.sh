#!/usr/bin/env bash
# build.sh — build the LFRic Apps Spack environment.
#
# This is the bulk of the original walkthrough.sh / install.sh: it produces a
# complete, activatable Spack environment (rose, cylc, psyclone, xios, mpich,
# ...). It does NOT compile lfric_atm — that needs SSH access to private physics
# repos (casim/jules/socrates) and lives in build-lfric-atm.sh.
#
# All heavy output goes under working_dir/ (git-ignored). Re-runs are cheap:
# Spack skips already-built, content-addressed packages.
set -uo pipefail

_here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=scripts/common.sh
. "$_here/common.sh"

SPACK_JOBS="${SPACK_JOBS:-8}"
# A few packages bundle LLVM/V8, whose largest translation units use several GB
# each; at high -j on a swapless/shared node they OOM (cc1plus gets SIGKILLed).
# Build those at a capped -j (HEAVY_JOBS) before the rest. HEAVY_PKGS lists them.
HEAVY_JOBS="${HEAVY_JOBS:-${NODE_JS_JOBS:-6}}"
HEAVY_PKGS=(${HEAVY_PKGS:-node-js rust})
COMPILER_SPEC="${COMPILER_SPEC:-gcc@14.3.0}"
COMPILER_SPEC="${COMPILER_SPEC#%}"
# Cray PrgEnv-gnu provides the compiler (gcc-native/14 == /usr/bin/gcc-14 ==
# gcc@14.3.0) AND the cray-mpich/libfabric/cray-pmi used as externals.
# craype-arm-grace selects the Neoverse-V2 (Grace) CPU target.
PRGENV_MODULE="${PRGENV_MODULE:-PrgEnv-gnu}"
CRAYPE_TARGET="${CRAYPE_TARGET:-craype-arm-grace}"
# Cray parallel HDF5 + netCDF-C/Fortran, used as Spack externals (spack.yaml).
# Not part of the default PrgEnv-gnu: they live under the cray-mpich module
# hierarchy (load AFTER PrgEnv-gnu) and default to an older version — so pin
# them. Versions must match the external prefixes in spack-env/spack.yaml.
HDF5_MODULE="${HDF5_MODULE:-cray-hdf5-parallel/1.14.3.9}"
NETCDF_MODULE="${NETCDF_MODULE:-cray-netcdf-hdf5parallel/4.9.2.3}"

info() { echo "INFO: $*"; }
warn() { echo "WARN: $*" >&2; }
die()  { echo "ERROR: $*" >&2; exit 1; }

mkdir -p "$WORKING_DIR" "$SPACK_USER_CONFIG_PATH" "$SPACK_USER_CACHE_PATH"

# --- 0. Submodules present? ------------------------------------------------
for sub in spack spack-packages lfric_apps lfric_core mo-spack-packages; do
  git -C "$REPO_ROOT/vendor/$sub" rev-parse --git-dir >/dev/null 2>&1 \
    || die "Submodule vendor/$sub is missing. Run: pixi run submodule-init"
done

# --- 1. Apply patches (idempotent; build is self-contained) ----------------
info "Applying patches"
bash "$_here/patch-all.sh" || die "patch-all failed"

# --- 2. Cray PrgEnv-gnu toolchain + cray-mpich -----------------------------
# The environment builds on the Cray PE GNU stack: gcc@14.3.0 (== gcc-native/14
# == /usr/bin/gcc-14) as the compiler and the system cray-mpich as the MPI —
# both pinned as externals in spack-env/spack.yaml. Loading PrgEnv-gnu is now
# REQUIRED (not a nicety): it puts cray-mpich/libfabric/cray-pmi on the module
# path so their externals resolve, and sets the CRAY_* lib paths needed at
# build/link time. craype-arm-grace selects the Neoverse-V2 (Grace) target.
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
# cray-hdf5-parallel / cray-netcdf-hdf5parallel back the hdf5/netcdf-c/
# netcdf-fortran externals in spack.yaml. Spack resolves those via their pinned
# prefixes, but loading the modules here puts the same (parallel, gnu/12.3) lib
# dirs on CRAY_LD_LIBRARY_PATH/PKG_CONFIG_PATH — which env-runtime.sh captures so
# view binaries linking HDF5/netCDF resolve their .so at runtime.
module load "$HDF5_MODULE" "$NETCDF_MODULE" \
  || die "could not load $HDF5_MODULE / $NETCDF_MODULE (parallel Cray HDF5/netCDF backing the spack.yaml externals)"
GCC_FC="${GCC_FC:-/usr/bin/gfortran-14}"
if [ -x "$GCC_FC" ]; then
  info "gcc (external): $("$GCC_FC" --version 2>/dev/null | head -1)"
else
  warn "$GCC_FC missing — the env's gcc external (spack.yaml) may not build Fortran"
fi
if [ -n "${CRAY_MPICH_DIR:-}" ] && [ -d "${CRAY_MPICH_DIR:-/nonexistent}" ]; then
  info "cray-mpich: $CRAY_MPICH_DIR (v${CRAY_MPICH_VERSION:-?})"
else
  die "CRAY_MPICH_DIR unset/missing after 'module load $PRGENV_MODULE' — cray-mpich external cannot resolve"
fi

# --- 3. XIOS source verification (non-fatal) -------------------------------
if [ "${RUN_XIOS_VERIFICATION:-1}" = "1" ]; then
  info "Verifying XIOS source (set RUN_XIOS_VERIFICATION=0 to skip)"
  XIOS_WORKDIR="$WORKING_DIR/xios-verification" bash "$_here/xios-verification.sh" \
    || warn "XIOS verification failed; continuing (the xios Spack package pins the same commit)"
fi

# --- 4. Bootstrap Spack ----------------------------------------------------
[ -f "$SPACK_ROOT/share/spack/setup-env.sh" ] || die "vendored spack missing setup-env.sh"
# shellcheck source=/dev/null
. "$SPACK_ROOT/share/spack/setup-env.sh"
spack --version || die "spack unavailable after sourcing setup-env.sh"

# --- 5. Repo-local install tree + caches -----------------------------------
# Without this, Spack would install into vendor/spack/opt (inside the submodule).
cat > "$SPACK_USER_CONFIG_PATH/config.yaml" <<EOF
config:
  install_tree:
    root: $WORKING_DIR/opt
  build_stage:
  - $WORKING_DIR/stage
  source_cache: $WORKING_DIR/source-cache
  misc_cache: $WORKING_DIR/misc-cache
  build_jobs: $SPACK_JOBS
EOF

# --- 6. Compilers ----------------------------------------------------------
# The compiler is declared as an explicit external in spack-env/spack.yaml
# (gcc@14.3.0) and pinned via per-language requires, so we deliberately do NOT
# run `spack compiler find`: with the env active (pixi activates it) that would
# rewrite the tracked spack.yaml, and a stray gcc on PATH could derail the solve.
info "Using gcc external pinned in spack.yaml ($COMPILER_SPEC)"

# --- 7. Sanity: environment repos resolve (incl. vendored builtin) ---------
info "Environment package repos:"
spack -e "$SPACK_ENV_DIR" repo list || die "spack repo list failed (check spack-env/spack.yaml repo paths)"

# --- 8. Concretize ---------------------------------------------------------
# --fresh: this is a pinned, reproducible env (submodule-pinned spack +
# spack-packages), so a fresh solve is deterministic and avoids reusing stale
# specs from an earlier (self-built-mpich) install tree. `install` still skips
# already-built identical hashes, so a fresh solve is not wasteful.
info "Concretizing $ENV_NAME"
spack -e "$SPACK_ENV_DIR" concretize -f --fresh || die "concretize failed"

# MPI must be the system cray-mpich (see providers in spack.yaml). Fail loudly
# if a from-source mpich/openmpi entered the DAG (e.g. the external stopped
# resolving): that defeats the cray-mpich switch and risks a gfortran .mod
# mismatch against our gcc@14.3.0.
if grep -qE '"name":[[:space:]]*"(mpich|openmpi)"' "$SPACK_ENV_DIR/spack.lock" 2>/dev/null; then
  die "a from-source MPI (mpich/openmpi) entered the solve; expected only cray-mpich. Is PrgEnv-gnu loaded and the cray-mpich external resolving?"
fi
info "MPI provider: cray-mpich (external) — OK"

# Likewise assert the Cray parallel HDF5/netCDF externals resolved: their prefixes
# must appear in the solve. If an external stopped resolving, Spack would silently
# build hdf5/netcdf-c from source — defeating the system-library switch and risking
# a gfortran .mod mismatch against gcc@14.3.0.
for _ext in /opt/cray/pe/hdf5-parallel /opt/cray/pe/netcdf-hdf5parallel; do
  grep -q "$_ext" "$SPACK_ENV_DIR/spack.lock" 2>/dev/null \
    || die "expected external prefix $_ext in the solve; hdf5/netcdf may have gone from-source. Are cray-hdf5-parallel/cray-netcdf-hdf5parallel loaded and the spack.yaml externals resolving?"
done
info "HDF5/netCDF provider: cray-hdf5-parallel + cray-netcdf-hdf5parallel (external) — OK"

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

# --- 11. Resolve runtime env once -> working_dir/env-runtime.sh ------------
info "Writing runtime snippet (working_dir/env-runtime.sh)"
view="$SPACK_ENV_DIR/.spack-env/view"
runtime="$WORKING_DIR/env-runtime.sh"
{
  echo "# Generated by build.sh on $(date -u '+%Y-%m-%dT%H:%M:%SZ'). Do not edit."
  echo "export PATH=\"$view/bin:\$PATH\""
  # Spack package scripts (e.g. psyclone) carry a shebang to the base python,
  # whose sys.path lacks the env's site-packages. Export the view's
  # site-packages so those scripts can import their own modules.
  for _sp in "$view"/lib/python*/site-packages; do
    [ -d "$_sp" ] && echo "export PYTHONPATH=\"$_sp\${PYTHONPATH:+:\$PYTHONPATH}\""
  done
  if shumlib_prefix="$(spack -e "$SPACK_ENV_DIR" location -i shumlib 2>/dev/null)"; then
    echo "export SHUMLIB_ROOT=\"$shumlib_prefix\""
    if [ -d "$shumlib_prefix/lib" ]; then
      echo "export LDFLAGS=\"\${LDFLAGS:+\$LDFLAGS }-L$shumlib_prefix/lib -Wl,-rpath=$shumlib_prefix/lib\""
      echo "export LIBRARY_PATH=\"$shumlib_prefix/lib\${LIBRARY_PATH:+:\$LIBRARY_PATH}\""
      echo "export LD_LIBRARY_PATH=\"$shumlib_prefix/lib\${LD_LIBRARY_PATH:+:\$LD_LIBRARY_PATH}\""
    fi
  fi
  # Cray MPI stack (cray-mpich + libfabric + cray-pmi) runtime libraries. They
  # live under /opt/cray (off the default loader path); CRAY_LD_LIBRARY_PATH —
  # set by the PrgEnv-gnu modules build.sh loaded — aggregates them. Export it so
  # view binaries that link MPI resolve their .so at runtime. (The MPI compiler
  # on this system is the Cray `ftn` wrapper from PrgEnv-gnu; build-lfric-atm.sh
  # loads PrgEnv-gnu itself, so FC is not pinned here.)
  if [ -n "${CRAY_MPICH_DIR:-}" ]; then
    _cray_libs="$CRAY_MPICH_DIR/lib${CRAY_LD_LIBRARY_PATH:+:$CRAY_LD_LIBRARY_PATH}"
    echo "export LD_LIBRARY_PATH=\"$_cray_libs\${LD_LIBRARY_PATH:+:\$LD_LIBRARY_PATH}\""
  fi
  if python_prefix="$(spack -e "$SPACK_ENV_DIR" location -i python 2>/dev/null)"; then
    echo "export PATH=\"$python_prefix/bin:\$PATH\""
  fi
  if psyclone_prefix="$(spack -e "$SPACK_ENV_DIR" location -i py-psyclone 2>/dev/null)"; then
    echo "export PATH=\"$psyclone_prefix/bin:\$PATH\""
    # The psyclone launcher's shebang python cannot locate its config; point at it.
    [ -f "$psyclone_prefix/share/psyclone/psyclone.cfg" ] \
      && echo "export PSYCLONE_CONFIG=\"$psyclone_prefix/share/psyclone/psyclone.cfg\""
  fi
  if rose_picker_prefix="$(spack -e "$SPACK_ENV_DIR" location -i rose-picker 2>/dev/null)"; then
    echo "export PATH=\"$rose_picker_prefix/bin:\$PATH\""
  fi
  echo "export APPS_ROOT_DIR=\"$REPO_ROOT/vendor/lfric_apps\""
  echo "export CORE_ROOT_DIR=\"$REPO_ROOT/vendor/lfric_core\""
  echo "export LFRIC_TARGET_PLATFORM=\"${LFRIC_TARGET_PLATFORM:-meto-spice}\""
  echo "export FPP=\"${FPP:-cpp -traditional-cpp}\""
} > "$runtime"

# --- 12. Cylc user config (idempotent; mirrors the old activate.sh) --------
setup_cylc_config() {
  local run_base_root run_base conf conf_dir run_start run_end plat_start plat_end
  run_base_root="${CYLC_RUN_BASE_ROOT:-${PROJECTDIR:-${SCRATCH:-$HOME}}}"
  run_base="${CYLC_RUN_BASE:-$run_base_root/${USER}/cylc-run}"
  conf="${CYLC_USER_CONF:-$HOME/.cylc/flow/global.cylc}"
  conf_dir="$(dirname "$conf")"
  run_start="# BEGIN LFRIC_CYLC_RUN_DIR";   run_end="# END LFRIC_CYLC_RUN_DIR"
  plat_start="# BEGIN LFRIC_ISAMBARD3_PLATFORM"; plat_end="# END LFRIC_ISAMBARD3_PLATFORM"

  mkdir -p "$conf_dir" "$run_base" 2>/dev/null || true
  [ -f "$conf" ] || : > "$conf"

  if grep -q "$run_start" "$conf" 2>/dev/null; then
    awk -v s="$run_start" -v e="$run_end" -v run="$run_base" '
      $0==s {inb=1; print; print "[install]"; print "    [[symlink dirs]]";
             print "        [[[localhost]]]"; print "            run = " run; next}
      $0==e {inb=0; print; next} !inb{print}' "$conf" > "$conf.tmp" && mv "$conf.tmp" "$conf"
  else
    cat >> "$conf" <<EOF

$run_start
[install]
    [[symlink dirs]]
        [[[localhost]]]
            run = $run_base
$run_end
EOF
  fi

  local plat_dir="$conf_dir/platforms.d" plat_file
  plat_file="$plat_dir/isambard3.cylc"
  mkdir -p "$plat_dir" 2>/dev/null || true
  if [ ! -f "$plat_file" ]; then
    cat > "$plat_file" <<EOF
$plat_start
[platforms]
    [[isambard3]]
        hosts = localhost
        job runner = slurm
        install target = localhost
$plat_end
EOF
  fi
}
if [ "${SETUP_CYLC_CONFIG:-1}" = "1" ]; then
  info "Configuring ~/.cylc (run dir + isambard3 platform)"
  setup_cylc_config || warn "cylc config setup failed (environment still usable)"
fi

# --- 13. Smoke test --------------------------------------------------------
# shellcheck source=/dev/null
. "$_here/activate.sh"
info "rose:     $(rose --version 2>&1 || echo MISSING)"
info "cylc:     $(cylc --version 2>&1 || echo MISSING)"
info "psyclone: $(psyclone --version 2>&1 || echo MISSING)"

echo ""
echo "BUILD_OK — environment built. Activate with: pixi run activate (or any 'pixi run ...')."
