#!/usr/bin/env bash
# stage1/lib.sh — the build, broken into phases.
#
# SOURCE this; do not run it. Every driver (concretize.sh, fetch.sh, build.sh)
# is just an ordered list of the lfric_* functions below, so what each entry
# point does is readable in ten lines and the phases stay individually testable.
#
# All configuration arrives via the environment, already exported by env.sh
# through pixi's activation hook. Nothing here computes a path.

# Definitions only; re-sourcing is harmless but pointless.
if [ -n "${_LFRIC_LIB_SOURCED:-}" ]; then return 0; fi
_LFRIC_LIB_SOURCED=1

info() { echo "INFO: $*"; }
warn() { echo "WARN: $*" >&2; }
die()  { echo "ERROR: $*" >&2; exit 1; }

# env.sh runs as a pixi activation script, so it has always run by now. If it
# has not, someone invoked a driver directly and every path below would be wrong.
[ -n "${STAGE1_DIR:-}" ] || {
  echo "ERROR: STAGE1_DIR unset — env.sh did not run. Stage 1 runs through pixi:" >&2
  echo "         cd stage1 && pixi run build        (see stage1/README.md)" >&2
  exit 1
}

# --- Tunables --------------------------------------------------------------
# Parallelism for the install. build.sbatch sets this from --cpus-per-task.
SPACK_JOBS="${SPACK_JOBS:-8}"
# node-js and rust (LLVM/V8) and xios (group_template_decl.cpp) have single
# translation units needing several GB each. Build them first at a capped -j so
# a full-width build does not OOM-kill cc1plus halfway through.
HEAVY_JOBS="${HEAVY_JOBS:-6}"
HEAVY_PKGS="node-js rust xios"

# Cray PE modules backing the cray variant's externals. These versions MUST
# match the external prefixes in spack-env/cray/spack.yaml — bumping one means
# bumping the other, or the solve silently falls back to a from-source build.
PRGENV_MODULE="PrgEnv-gnu"
CRAYPE_TARGET="craype-arm-grace"
HDF5_MODULE="cray-hdf5-parallel/1.14.3.9"
NETCDF_MODULE="cray-netcdf-hdf5parallel/4.9.2.3"
# The compiler, declared as an external in spack-env/common.yaml.
GCC_FC="/usr/bin/gfortran-14"

# --- Preflight -------------------------------------------------------------

# pixi pins python 3.11, so this only fires if someone overrode SPACK_PYTHON.
lfric_check_python() {
  local ver
  [ -x "${SPACK_PYTHON:-}" ] || die "SPACK_PYTHON is not an executable: '${SPACK_PYTHON:-}'"
  ver="$("$SPACK_PYTHON" -c 'import sys; print("%d.%d" % sys.version_info[:2])')"
  case "$ver" in
    3.7|3.8|3.9|3.10|3.11) info "Spack Python: $SPACK_PYTHON ($ver)" ;;
    *) die "Spack needs Python >=3.7 and <3.12 (found $ver at $SPACK_PYTHON). Spack 1.0 parses sources with ast.Str, removed in 3.12." ;;
  esac
}

# An initialized submodule has its own .git; an uninitialized one is an empty
# directory. Test that file directly — `git rev-parse` inside an empty submodule
# dir walks UP to the superproject and misleadingly succeeds.
lfric_check_submodules() {
  local sub
  for sub in spack spack-packages mo-spack-packages; do
    [ -e "$STAGE1_DIR/vendor/$sub/.git" ] \
      || die "vendor/$sub is not initialized. Run: pixi run submodules  (mo-spack-packages is private — it needs an SSH key with Met Office SSO)"
  done
}

lfric_apply_patches() {
  local f
  for f in "$STAGE1_DIR"/patches/*.sh; do
    [ -f "$f" ] || continue
    info "Applying patch: $(basename "$f")"
    bash "$f" || die "patch failed: $f"
  done
}

# Load the modules backing the cray variant's externals. gcc@14.3.0 is an
# external for BOTH variants (it is the system /usr/bin/gcc-14, always present);
# only MPI and parallel I/O differ. PrgEnv-gnu is what puts cray-mpich,
# libfabric and cray-pmi on the module path so their externals resolve at all.
lfric_load_toolchain() {
  if [ "$LFRIC_STACK" = cray ]; then
    if ! command -v module >/dev/null 2>&1; then
      # shellcheck source=/dev/null
      . /opt/cray/pe/lmod/lmod/init/bash || die "no 'module' command and Lmod init not found"
    fi
    module load "$PRGENV_MODULE" || die "could not 'module load $PRGENV_MODULE' — the cray-mpich external will not resolve"
    module load "$CRAYPE_TARGET" 2>/dev/null || warn "could not load $CRAYPE_TARGET (target may default to plain aarch64)"
    module load "$HDF5_MODULE" "$NETCDF_MODULE" \
      || die "could not load $HDF5_MODULE / $NETCDF_MODULE (they back the externals in spack-env/cray/spack.yaml)"
    [ -d "${CRAY_MPICH_DIR:-/nonexistent}" ] \
      || die "CRAY_MPICH_DIR unset or missing after loading $PRGENV_MODULE — cray-mpich cannot resolve"
    info "cray-mpich: $CRAY_MPICH_DIR (v${CRAY_MPICH_VERSION:-?})"
  else
    info "LFRIC_STACK=spack: MPI and HDF5/netCDF come from source; loading no Cray modules"
  fi
  [ -x "$GCC_FC" ] || die "$GCC_FC missing — it is the compiler external declared in spack-env/common.yaml"
  info "gcc (external): $("$GCC_FC" --version | head -1)"
}

lfric_bootstrap_spack() {
  # shellcheck source=/dev/null
  . "$SPACK_ROOT/share/spack/setup-env.sh" || die "vendored spack missing share/spack/setup-env.sh"
  spack --version || die "spack unavailable after sourcing setup-env.sh"
}

# Spack's own config, written per-version under our prefix. install_tree is the
# persistent store; the source and misc caches sit at LFRIC_BASE so a new env
# version reuses what previous versions already downloaded; build_stage is the
# transient compile area on node-local disk.
lfric_write_config() {
  mkdir -p "$LFRIC_PREFIX" "$SPACK_USER_CONFIG_PATH" "$SPACK_USER_CACHE_PATH" "$LFRIC_WORKING_DIR"
  # mkdir -p succeeds for an existing directory even when it is not writable.
  [ -w "$LFRIC_WORKING_DIR" ] || die "build stage not writable: $LFRIC_WORKING_DIR (set LFRIC_WORKING_DIR)"
  info "Install prefix (persistent): $LFRIC_PREFIX"
  info "Build stage    (transient):  $LFRIC_WORKING_DIR"
  cat > "$SPACK_USER_CONFIG_PATH/config.yaml" <<EOF
config:
  install_tree:
    root: $LFRIC_PREFIX/opt
  build_stage:
  - $LFRIC_WORKING_DIR
  source_cache: $LFRIC_SOURCE_CACHE
  misc_cache: $LFRIC_MISC_CACHE
  build_jobs: $SPACK_JOBS
EOF
}

# Instantiate the Spack environment under LFRIC_PREFIX from the tracked
# template, rewriting its relative `include: ../common.yaml` to an absolute path
# back into this repo. The env's view and lockfile then live outside the repo,
# which is what lets the modulefile be loaded without the repo present.
# (The substitution is done with index()/substr() so nothing in the path is
# interpreted as a regex or a replacement escape.)
lfric_instantiate_env() {
  [ -f "$SPACK_ENV_TEMPLATE" ] || die "missing env template: $SPACK_ENV_TEMPLATE"
  mkdir -p "$SPACK_ENV_DIR"
  LFRIC_COMMON_YAML="$STAGE1_DIR/spack-env/common.yaml" \
    awk '{ i = index($0, "../common.yaml")
           if (i > 0) $0 = substr($0, 1, i-1) ENVIRON["LFRIC_COMMON_YAML"] substr($0, i + length("../common.yaml"))
           print }' "$SPACK_ENV_TEMPLATE" > "$SPACK_ENV_DIR/spack.yaml" \
    || die "failed to generate $SPACK_ENV_DIR/spack.yaml"
  grep -q "$STAGE1_DIR/spack-env/common.yaml" "$SPACK_ENV_DIR/spack.yaml" \
    || die "include rewrite produced no absolute common.yaml path in $SPACK_ENV_DIR/spack.yaml"
  info "Spack env instantiated at $SPACK_ENV_DIR (from $SPACK_ENV_TEMPLATE)"
  spack -e "$SPACK_ENV_DIR" repo list || die "spack repo list failed — check the repo paths in spack-env/common.yaml"
}

# Everything any driver needs before touching specs.
lfric_prepare() {
  info "Variant: LFRIC_STACK=$LFRIC_STACK   version: $LFRIC_ENV_VERSION"
  lfric_check_python
  lfric_check_submodules
  lfric_apply_patches
  lfric_load_toolchain
  lfric_bootstrap_spack
  lfric_write_config
  lfric_instantiate_env
}

# --- Solve -----------------------------------------------------------------
# `--fresh` keeps the solve deterministic (it ignores whatever is already in the
# install tree) and is a ~1 s no-op when the lock already matches the manifest.
lfric_concretize() {
  info "Concretizing $ENV_NAME"
  if [ "${FORCE_CONCRETIZE:-0}" = "1" ]; then
    spack -e "$SPACK_ENV_DIR" concretize -f --fresh || die "concretize failed"
  else
    spack -e "$SPACK_ENV_DIR" concretize --fresh || die "concretize failed"
  fi
  lfric_assert_variant
}

# Assert the lock actually matches the requested variant. This is the guard that
# stops a leaking PrgEnv, or an external that quietly stopped resolving, from
# producing a silently wrong stack — a from-source mpich in the cray variant
# would build and install fine, then have no working multi-node MPI. Keep it.
lfric_assert_variant() {
  local lock="$SPACK_ENV_DIR/spack.lock" ext
  if [ "$LFRIC_STACK" = cray ]; then
    ! grep -qE '"name":[[:space:]]*"(mpich|openmpi)"' "$lock" \
      || die "a from-source MPI entered the cray solve; expected only cray-mpich. Is PrgEnv-gnu loaded?"
    for ext in /opt/cray/pe/hdf5-parallel /opt/cray/pe/netcdf-hdf5parallel; do
      grep -q "$ext" "$lock" \
        || die "expected the external prefix $ext in the solve; HDF5/netCDF may have gone from-source. Are the cray-hdf5-parallel/cray-netcdf-hdf5parallel modules loaded, and do their versions match spack-env/cray/spack.yaml?"
    done
    info "Providers OK: cray-mpich + Cray HDF5/netCDF, all external"
  else
    ! grep -qE '"name":[[:space:]]*"cray-mpich"' "$lock" \
      || die "cray-mpich entered the spack solve; a Cray PrgEnv is leaking into the environment"
    grep -qE '"name":[[:space:]]*"mpich"' "$lock" \
      || die "no from-source mpich in the spack solve (the MPI provider did not resolve to mpich)"
    ! grep -qE '/opt/cray/pe/(hdf5-parallel|netcdf-hdf5parallel)' "$lock" \
      || die "a Cray HDF5/netCDF external entered the spack solve; expected from-source"
    info "Providers OK: from-source mpich + hdf5/netcdf"
  fi
}

# --- Fetch -----------------------------------------------------------------
lfric_fetch() {
  info "Fetching all sources for $ENV_NAME into $LFRIC_SOURCE_CACHE"
  spack -e "$SPACK_ENV_DIR" fetch || die "spack fetch failed"
  info "Sources cached — the compute-node build now has nothing to download."
}

# --- Install ---------------------------------------------------------------
# The order is deliberate: libxml2 first (some netcdf-c builds probe
# xml2-config), then yaxt alone (it has a parallel-make race), then the memory-
# hungry packages at a capped -j, then everything else at full width.
lfric_install() {
  info "Installing libxml2 (first: netcdf-c probes xml2-config)"
  spack -e "$SPACK_ENV_DIR" install -j "$SPACK_JOBS" libxml2 || die "install libxml2 failed"
  local libxml2_prefix
  if libxml2_prefix="$(spack -e "$SPACK_ENV_DIR" location -i libxml2 2>/dev/null)"; then
    export XML2_CONFIG="$libxml2_prefix/bin/xml2-config" PATH="$libxml2_prefix/bin:$PATH"
  fi

  info "Installing yaxt (serial: it has a parallel-make race)"
  spack -e "$SPACK_ENV_DIR" install -j 1 yaxt || die "install yaxt failed"

  # Only pre-build the heavy packages this environment actually contains. Match
  # the lock's key WITHOUT assuming whitespace: Spack writes it compactly, as
  # `"name":"xios"`. A pattern with a space after the colon silently matches
  # nothing, which disables this cap entirely and lets xios compile at full
  # width — the exact OOM this function exists to avoid. Say what is skipped
  # rather than dropping it quietly.
  #
  # There is deliberately no "is it already installed?" pre-check: `spack
  # install` on an installed package is a fast no-op, and the obvious check
  # (`spack find`) reports an environment's concretized specs whether or not
  # they are installed.
  local hp
  for hp in $HEAVY_PKGS; do
    if ! grep -qE "\"name\":[[:space:]]*\"$hp\"" "$SPACK_ENV_DIR/spack.lock"; then
      info "$hp is not in this environment — skipping its capped pre-build"
      continue
    fi
    info "Installing $hp (-j $HEAVY_JOBS; multi-GB translation units)"
    spack -e "$SPACK_ENV_DIR" install -j "$HEAVY_JOBS" "$hp" || die "install $hp failed"
  done

  info "Installing the full environment (-j $SPACK_JOBS)"
  spack -e "$SPACK_ENV_DIR" install -j "$SPACK_JOBS" || die "install failed"
}

lfric_regenerate_view() {
  if ! spack -e "$SPACK_ENV_DIR" env view regenerate; then
    rm -rf "$SPACK_ENV_DIR/.spack-env/._view"
    spack -e "$SPACK_ENV_DIR" env view regenerate || die "view regenerate failed"
  fi
}

lfric_gen_modulefile() {
  bash "$STAGE1_DIR/gen-modulefile.sh" || die "gen-modulefile.sh failed"
}

# Load the modulefile we just wrote, exactly as an end user would, and check the
# tools it is supposed to provide are there. This is the acceptance test for the
# whole build: if it passes, `module load` is a sufficient contract.
lfric_smoke_test() {
  command -v module >/dev/null 2>&1 || . /opt/cray/pe/lmod/lmod/init/bash
  module use "$MODULEFILES_DIR"
  module load "$MODULE_NAME" || die "could not load the modulefile we just wrote ($MODULE_NAME)"
  info "rose:     $(rose --version 2>&1 || echo MISSING)"
  info "cylc:     $(cylc --version 2>&1 || echo MISSING)"
  info "psyclone: $(psyclone --version 2>&1 || echo MISSING)"
  info "FC=${FC:-UNSET}  CXX=${CXX:-UNSET}  LDMPI=${LDMPI:-UNSET}"
  # The toolchain is the contract, so treat a missing compiler as a build failure
  # rather than something the first consumer discovers.
  [ -n "${FC:-}" ] || die "$MODULE_NAME did not set FC — the module is not a usable toolchain"
  command -v "$FC" >/dev/null 2>&1 || die "FC=$FC is not on PATH after loading $MODULE_NAME"
  "$FC" --version 2>&1 | head -1
}
