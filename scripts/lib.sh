#!/usr/bin/env bash
# lib.sh — the Stage-1 build phases as sourceable functions.
#
# SOURCE this (after common.sh); do not execute it. It defines the discrete
# phases that the thin Stage-1 drivers compose, so each concern is callable on
# its own and concretization (the dependency SOLVE) is no longer hidden behind a
# flag inside the install driver:
#
#   concretize.sh : lfric_prepare + lfric_concretize              (cheap solve/check)
#   build.sh      : + lfric_install + view/modulefile/smoke        (the full build)
#   fetch.sh      : + lfric_fetch (after a login-node submodule clone)
#
# Deeper rationale (variants, modulefile, OOM, …) lives in MAINTAINER.md.

# Source-once guard (these are pure definitions; re-sourcing is harmless but
# pointless). `return` is valid only when sourced, which is the only supported use.
if [ -n "${_LFRIC_LIB_SOURCED:-}" ]; then return 0; fi
_LFRIC_LIB_SOURCED=1

# Directory holding the task scripts (this file's own dir), for calling siblings.
LFRIC_SCRIPTS_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"

# --- Logging ---------------------------------------------------------------
# die exits; in a sourced function called from a (run) driver that terminates the
# driver, which is the intended abort behaviour.
info() { echo "INFO: $*"; }
warn() { echo "WARN: $*" >&2; }
die()  { echo "ERROR: $*" >&2; exit 1; }

# --- Tunables (maintainer overrides; see MAINTAINER.md) --------------------
SPACK_JOBS="${SPACK_JOBS:-8}"
# node-js/rust (LLVM/V8) and xios (group_template_decl.cpp) have translation units
# that use several GB each; build them first at a capped -j to avoid OOM kills.
HEAVY_JOBS="${HEAVY_JOBS:-${NODE_JS_JOBS:-6}}"
# Deliberate word-splitting so `HEAVY_PKGS="pkg1 pkg2"` overrides cleanly.
# shellcheck disable=SC2206
HEAVY_PKGS=(${HEAVY_PKGS:-node-js rust xios})
COMPILER_SPEC="${COMPILER_SPEC:-gcc@14.3.0}"; COMPILER_SPEC="${COMPILER_SPEC#%}"
# cray variant: Cray PE modules backing the cray-mpich + HDF5/netCDF externals.
PRGENV_MODULE="${PRGENV_MODULE:-PrgEnv-gnu}"
CRAYPE_TARGET="${CRAYPE_TARGET:-craype-arm-grace}"
# HDF5/netCDF module versions must match the external prefixes in cray/spack.yaml.
HDF5_MODULE="${HDF5_MODULE:-cray-hdf5-parallel/1.14.3.9}"
NETCDF_MODULE="${NETCDF_MODULE:-cray-netcdf-hdf5parallel/4.9.2.3}"
GCC_FC="${GCC_FC:-/usr/bin/gfortran-14}"

# The Stage-1 (core) submodules every solve/build needs.
LFRIC_CORE_SUBMODULES=(spack spack-packages lfric_apps lfric_core mo-spack-packages)

# --- Preflight -------------------------------------------------------------
lfric_validate_variant() {
  case "$LFRIC_STACK" in
    cray|spack) ;;
    *) die "LFRIC_STACK must be 'cray' or 'spack' (got '$LFRIC_STACK')" ;;
  esac
  info "Dependency stack variant: LFRIC_STACK=$LFRIC_STACK (env: $SPACK_ENV_DIR)"
}

# Spack 1.0 needs CPython >=3.7 and <3.12 (it parses sources with ast.Str, removed
# in 3.12). common.sh points SPACK_PYTHON at python3; verify it here for a clear
# error rather than a deep Spack traceback later.
lfric_check_python() {
  local py ver
  py="${SPACK_PYTHON:-$(command -v python3 2>/dev/null || true)}"
  [ -n "$py" ] && [ -x "$py" ] \
    || die "no Python found to run Spack. Load one ('module load cray-python/3.11.7', or any python3 in [3.7,3.12)) and re-run — or use pixi."
  ver="$("$py" -c 'import sys; print("%d.%d" % sys.version_info[:2])' 2>/dev/null || true)"
  case "$ver" in
    3.7|3.8|3.9|3.10|3.11) info "Spack Python: $py ($ver)" ;;
    *) die "Spack needs Python >=3.7 and <3.12 (found '${ver:-unknown}' at $py). Load a suitable one ('module load cray-python/3.11.7') — or use pixi." ;;
  esac
}

lfric_ensure_dirs() {
  mkdir -p "$PREFIX" "$SPACK_USER_CONFIG_PATH" "$SPACK_USER_CACHE_PATH"
}

# build/concretize: the core submodules must already be present (fail with a hint).
lfric_check_submodules() {
  local sub
  for sub in "${LFRIC_CORE_SUBMODULES[@]}"; do
    git -C "$REPO_ROOT/vendor/$sub" rev-parse --git-dir >/dev/null 2>&1 \
      || die "Submodule vendor/$sub is missing. Run: pixi run submodule-init  (or: git submodule update --init --recursive --jobs 4 -- ${LFRIC_CORE_SUBMODULES[*]/#/vendor/})"
  done
}

# fetch: clone any MISSING core submodules instead of failing, so the login-node
# prefetch is self-sufficient. Concurrency-capped ($1, default 4) and propagated
# to recursive sub-levels via submodule.fetchJobs (set by the caller) — login
# nodes have a small ulimit -u.
lfric_clone_missing_submodules() {
  local jobs="${1:-4}" sub missing=()
  for sub in "${LFRIC_CORE_SUBMODULES[@]}"; do
    git -C "$REPO_ROOT/vendor/$sub" rev-parse --git-dir >/dev/null 2>&1 \
      || missing+=("vendor/$sub")
  done
  if [ "${#missing[@]}" -gt 0 ]; then
    info "Cloning missing Stage-1 submodules (--jobs $jobs): ${missing[*]}"
    git -C "$REPO_ROOT" submodule update --init --recursive --jobs "$jobs" -- "${missing[@]}" \
      || die "submodule init failed for: ${missing[*]} (private repos need Met Office SSO on your SSH key)"
  else
    info "Stage-1 submodules already present — skipping clone"
  fi
}

lfric_apply_patches() {
  info "Applying patches"
  bash "$LFRIC_SCRIPTS_DIR/patch-all.sh" || die "patch-all failed"
}

# Load the toolchain + MPI/IO modules. gcc@14.3.0 is an external (common.yaml) for
# BOTH variants; LFRIC_STACK decides the MPI + parallel I/O provider. For cray,
# PrgEnv-gnu is REQUIRED — it puts cray-mpich/libfabric/cray-pmi on the module path
# (so their externals resolve) and sets the CRAY_* lib paths used at build/link.
lfric_load_toolchain() {
  if [ "$LFRIC_STACK" = cray ]; then
    if ! command -v module >/dev/null 2>&1; then
      local f
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
  if [ -x "$GCC_FC" ]; then
    info "gcc (external): $("$GCC_FC" --version 2>/dev/null | head -1)"
  else
    warn "$GCC_FC missing — the env's gcc external (common.yaml) may not build Fortran"
  fi
}

lfric_bootstrap_spack() {
  [ -f "$SPACK_ROOT/share/spack/setup-env.sh" ] || die "vendored spack missing setup-env.sh"
  # shellcheck source=/dev/null
  . "$SPACK_ROOT/share/spack/setup-env.sh"
  spack --version || die "spack unavailable after sourcing setup-env.sh"
}

# Write Spack's config under PREFIX: install_tree + caches persist (so built
# packages + downloaded sources survive a re-run); build_stage is the transient,
# metadata-heavy compile area (node-local NVMe on a compute node). See MAINTAINER.md.
lfric_write_config() {
  local build_stage="$WORKING_DIR"
  mkdir -p "$build_stage" || die "build stage not writable: $build_stage (set LFRIC_WORKING_DIR)"
  info "Install prefix (persistent):   $PREFIX"
  info "Build stage    (transient):    $build_stage"
  cat > "$SPACK_USER_CONFIG_PATH/config.yaml" <<EOF
config:
  install_tree:
    root: $PREFIX/opt
  build_stage:
  - $build_stage
  source_cache: $PREFIX/source-cache
  misc_cache: $PREFIX/misc-cache
  build_jobs: $SPACK_JOBS
EOF
}

# Instantiate the directory environment under PREFIX from the tracked template,
# rewriting the relative `include: ../common.yaml` to an absolute path back into
# the repo (done literally in awk via index()/substr so nothing in the path is
# interpreted). The env's view + lockfile then land outside the repo. See MAINTAINER.md.
lfric_instantiate_env() {
  [ -f "$SPACK_ENV_TEMPLATE" ] || die "missing env template: $SPACK_ENV_TEMPLATE"
  mkdir -p "$SPACK_ENV_DIR"
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
}

lfric_check_repos() {
  info "Environment package repos:"
  spack -e "$SPACK_ENV_DIR" repo list || die "spack repo list failed (check spack-env/common.yaml repo paths)"
}

# Everything a solve / install / fetch needs before touching specs: validate the
# variant, check Python + submodules, apply patches, load the toolchain modules,
# bootstrap Spack, write config and instantiate the environment.
lfric_prepare() {
  lfric_validate_variant
  lfric_check_python
  lfric_ensure_dirs
  lfric_check_submodules
  lfric_apply_patches
  lfric_load_toolchain
  lfric_bootstrap_spack
  lfric_write_config
  lfric_instantiate_env
  lfric_check_repos
}

# --- Concretize (the dependency SOLVE) -------------------------------------
# Idempotent: plain `--fresh` is a no-op (~1s) when the lock already matches the
# manifest, and re-solves freshly when the manifest changed. FORCE_CONCRETIZE=1
# adds -f to force a full re-solve. --fresh keeps the solve deterministic for this
# pinned env (it ignores any stale specs already in the install tree). The lock is
# install-prefix-independent, so the solve does not depend on PREFIX's contents.
lfric_concretize() {
  info "Concretizing $ENV_NAME"
  local cflags=(--fresh)
  [ "${FORCE_CONCRETIZE:-0}" = "1" ] && cflags=(-f --fresh)
  spack -e "$SPACK_ENV_DIR" concretize "${cflags[@]}" || die "concretize failed"
  lfric_assert_variant
}

# Assert the concretized lock actually matches the requested variant, so a
# mis-resolved external or a leaking PrgEnv can never silently produce the wrong
# stack. This is a guard on the build invariant — keep it.
lfric_assert_variant() {
  local lock="$SPACK_ENV_DIR/spack.lock" ext
  if [ "$LFRIC_STACK" = cray ]; then
    if grep -qE '"name":[[:space:]]*"(mpich|openmpi)"' "$lock" 2>/dev/null; then
      die "a from-source MPI (mpich/openmpi) entered the solve; expected only cray-mpich. Is PrgEnv-gnu loaded and the cray-mpich external resolving?"
    fi
    info "MPI provider: cray-mpich (external) — OK"
    for ext in /opt/cray/pe/hdf5-parallel /opt/cray/pe/netcdf-hdf5parallel; do
      grep -q "$ext" "$lock" 2>/dev/null \
        || die "expected external prefix $ext in the solve; hdf5/netcdf may have gone from-source. Are cray-hdf5-parallel/cray-netcdf-hdf5parallel loaded and the cray/spack.yaml externals resolving?"
    done
    info "HDF5/netCDF provider: cray-hdf5-parallel + cray-netcdf-hdf5parallel (external) — OK"
  else
    if grep -qE '"name":[[:space:]]*"cray-mpich"' "$lock" 2>/dev/null; then
      die "cray-mpich entered the LFRIC_STACK=spack solve; expected a from-source mpich. Is a Cray PrgEnv leaking into the environment?"
    fi
    if ! grep -qE '"name":[[:space:]]*"mpich"' "$lock" 2>/dev/null; then
      die "no from-source mpich in the LFRIC_STACK=spack solve (MPI provider did not resolve to mpich)."
    fi
    if grep -qE '/opt/cray/pe/(hdf5-parallel|netcdf-hdf5parallel)' "$lock" 2>/dev/null; then
      die "a Cray HDF5/netCDF external prefix entered the LFRIC_STACK=spack solve; expected from-source hdf5/netcdf."
    fi
    info "MPI/IO provider: from-source mpich + hdf5/netcdf — OK"
  fi
}

# --- Fetch -----------------------------------------------------------------
# Download/clone the source of every concretized spec into the persistent source
# cache. Externals (cray-mpich, Cray HDF5/netCDF) have no source and are skipped.
lfric_fetch() {
  info "Fetching all sources for $ENV_NAME into $PREFIX/source-cache"
  spack -e "$SPACK_ENV_DIR" fetch || die "spack fetch failed"
  info "Sources cached under $PREFIX/source-cache — the compute-node build can run offline."
}

# --- Install ---------------------------------------------------------------
# libxml2 first (some netcdf-c builds probe xml2-config), then yaxt serially (a
# known parallel race), then the heavy packages at a capped -j, then the rest.
lfric_install() {
  info "Installing libxml2 (serial pre-step)"
  spack -e "$SPACK_ENV_DIR" install -j "$SPACK_JOBS" libxml2 || die "install libxml2 failed"
  local libxml2_prefix
  if libxml2_prefix="$(spack -e "$SPACK_ENV_DIR" location -i libxml2 2>/dev/null)"; then
    export XML2_CONFIG="$libxml2_prefix/bin/xml2-config"
    export PATH="$libxml2_prefix/bin:$PATH"
  fi

  info "Installing yaxt (serial; avoids a parallel race)"
  spack -e "$SPACK_ENV_DIR" install -j 1 yaxt || die "install yaxt failed"

  local hp
  for hp in "${HEAVY_PKGS[@]}"; do
    if spack -e "$SPACK_ENV_DIR" find "$hp" >/dev/null 2>&1; then
      continue   # already installed
    fi
    # Only pre-build heavy pkgs actually in the concretized environment.
    if ! grep -q "\"name\": \"$hp\"" "$SPACK_ENV_DIR/spack.lock" 2>/dev/null; then
      info "$hp not in the concretized environment; skipping heavy pre-build"
      continue
    fi
    info "Installing $hp (-j $HEAVY_JOBS; bundles LLVM/V8 — capped to avoid OOM)"
    spack -e "$SPACK_ENV_DIR" install -j "$HEAVY_JOBS" "$hp" || die "install $hp failed"
  done

  info "Installing the full environment (-j $SPACK_JOBS)"
  spack -e "$SPACK_ENV_DIR" install -j "$SPACK_JOBS" || die "install (full environment) failed"
}

lfric_regenerate_view() {
  if ! spack -e "$SPACK_ENV_DIR" env view regenerate; then
    rm -rf "$SPACK_ENV_DIR/.spack-env/._view"
    spack -e "$SPACK_ENV_DIR" env view regenerate || die "view regenerate failed"
  fi
}

# Resolve the per-build view + package prefixes into the Lmod data-table
# modulefile (standalone, so it can be regenerated without a full rebuild).
lfric_gen_modulefile() {
  bash "$LFRIC_SCRIPTS_DIR/gen-modulefile.sh" || die "gen-modulefile.sh failed"
}

lfric_smoke_test() {
  # shellcheck source=/dev/null
  . "$LFRIC_SCRIPTS_DIR/activate.sh"
  info "rose:     $(rose --version 2>&1 || echo MISSING)"
  info "cylc:     $(cylc --version 2>&1 || echo MISSING)"
  info "psyclone: $(psyclone --version 2>&1 || echo MISSING)"
}

# --- XIOS source check (non-fatal; build only) -----------------------------
lfric_verify_xios() {
  [ "${RUN_XIOS_VERIFICATION:-1}" = "1" ] || return 0
  info "Verifying XIOS source (set RUN_XIOS_VERIFICATION=0 to skip)"
  XIOS_WORKDIR="$PREFIX/xios-verification" bash "$LFRIC_SCRIPTS_DIR/xios-verification.sh" \
    || warn "XIOS verification failed; continuing (the xios Spack package pins the same commit)"
}
