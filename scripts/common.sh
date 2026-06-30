#!/usr/bin/env bash
# Common environment for the build/task scripts. SOURCE this file; do not run it.
#
# Sets up the Stage-1 build context (vendored Spack, install PREFIX, selected
# variant) and puts the generated modulefiles on MODULEPATH so the built
# environment can be `module load`ed. Does NOT require pixi: pixi sources it via
# its activation hook, and `bash scripts/build.sh` (no pixi) sources it the same.
#
# Kept side-effect-light (only env vars + PATH) because it is sourced on every
# `pixi run`. Anything heavy (module loads, spack queries) lives in build.sh.
# Deeper rationale lives in MAINTAINER.md.

# --- Repo root -------------------------------------------------------------
# pixi exports PIXI_PROJECT_ROOT; otherwise derive it from this file's path.
if [ -n "${PIXI_PROJECT_ROOT:-}" ]; then
  REPO_ROOT="$PIXI_PROJECT_ROOT"
else
  REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")/.." && pwd)"
fi
export REPO_ROOT

# --- Vendored Spack (vendor/spack submodule) -------------------------------
export SPACK_ROOT="$REPO_ROOT/vendor/spack"

# --- Env version (CalVer) --------------------------------------------------
# The environment is versioned by LFRIC_ENV_VERSION (CalVer, e.g. v2026.06.30),
# committed in the repo's ./VERSION file. This keeps independent builds in
# DISTINCT prefixes instead of silently overwriting a shared install. The value
# is a plain read of ./VERSION (not inference); set LFRIC_ENV_VERSION to pin a
# build to a chosen version dir. Bump it deliberately with scripts/bump-env-
# version.sh (pixi run bump-env-version). NB: this is the ENVIRONMENT's version,
# distinct from any LFRic apps/core version.
if [ -z "${LFRIC_ENV_VERSION:-}" ]; then
  if [ -r "$REPO_ROOT/VERSION" ]; then
    LFRIC_ENV_VERSION="$(tr -d '[:space:]' < "$REPO_ROOT/VERSION")"
  fi
  LFRIC_ENV_VERSION="${LFRIC_ENV_VERSION:-unversioned}"
fi
export LFRIC_ENV_VERSION

# --- Build locations (the knobs that matter) -------------------------------
# BASE (LFRIC_PREFIX)   the per-arch container, SHARED across env versions. Lives
#   OUTSIDE the repo. Default $PROJECTDIR/$USER/opt/<sysname>-<machine> (falls back
#   to $SCRATCH/$HOME). LFRIC_PREFIX overrides BASE — versioning still applies under it.
# PREFIX                the VERSIONED install: $BASE/$LFRIC_ENV_VERSION. Holds the
#   Spack install tree (opt), the per-variant environment + view, and the per-version
#   Spack config. BOTH variants share this one PREFIX/opt. Distinct per version, so a
#   new version never overwrites an existing one.
# WORKING_DIR (LFRIC_WORKING_DIR)  transient Spack build/compile stage ONLY. It
#   is metadata-heavy, so on a compute node point it at node-local NVMe — the
#   sbatch sets LFRIC_WORKING_DIR=$LOCALDIR/... to keep the install phase off the
#   shared (and often contended) Lustre. Defaults to $PREFIX/stage.
_arch_tag="$(uname -sm | tr ' ' -)"
export BASE="${LFRIC_PREFIX:-${PROJECTDIR:-${SCRATCH:-$HOME}}/$USER/opt/$_arch_tag}"
unset _arch_tag
export PREFIX="$BASE/$LFRIC_ENV_VERSION"
export WORKING_DIR="${LFRIC_WORKING_DIR:-$PREFIX/stage}"

# Redirect Spack's user config + cache under PREFIX (per-version) so the build is
# hermetic: it neither reads nor writes the user's global ~/.spack.
export SPACK_USER_CONFIG_PATH="${SPACK_USER_CONFIG_PATH:-$PREFIX/spack-config}"
export SPACK_USER_CACHE_PATH="${SPACK_USER_CACHE_PATH:-$PREFIX/spack-cache}"

# Download caches: SHARED at BASE and version-INDEPENDENT — Spack's source-tarball
# cache and misc cache are content-addressed, so a new env version reuses already-
# downloaded sources instead of re-fetching (and never has to re-hit a flaky source
# host). lib.sh writes these into the per-version Spack config. Overridable.
export LFRIC_SOURCE_CACHE="${LFRIC_SOURCE_CACHE:-$BASE/source-cache}"
export LFRIC_MISC_CACHE="${LFRIC_MISC_CACHE:-$BASE/misc-cache}"

# --- Dependency stack variant (cray | spack) -------------------------------
# cray  - system cray-mpich + Cray parallel HDF5/netCDF (externals)  [default]
# spack - mpich + HDF5/netCDF built from source (portable fallback)
# Both share $PREFIX/opt; only the MPI-dependent subtree is built per variant.
# build.sh validates the value; kept default-only here to stay side-effect-light.
export LFRIC_STACK="${LFRIC_STACK:-cray}"
# The Spack directory environment is GENERATED under PREFIX (so its view +
# lockfile land outside the repo). The tracked spack-env/<variant>/spack.yaml is
# the TEMPLATE build.sh instantiates from. See MAINTAINER.md.
export SPACK_ENV_TEMPLATE="$REPO_ROOT/spack-env/$LFRIC_STACK/spack.yaml"
export SPACK_ENV_DIR="$PREFIX/spack-env/$LFRIC_STACK"
export ENV_NAME="lfric-apps-isambard-$LFRIC_STACK"
# Lmod activation. MODULE_NAME is what you `module load`; MODULEFILE backs it and
# doubles as the "is this variant built?" sentinel. The modulefiles live in ONE
# shared, version-INDEPENDENT tree ($BASE/modulefiles) and are keyed by version +
# variant (lfric-env/<version>/<variant>), so a single `module use $BASE/modulefiles`
# makes `module avail lfric-env` list every built version × variant side by side.
export MODULEFILES_DIR="$BASE/modulefiles"
export MODULE_NAME="lfric-env/$LFRIC_ENV_VERSION/$LFRIC_STACK"
export MODULEFILE="$MODULEFILES_DIR/lfric-env/$LFRIC_ENV_VERSION/$LFRIC_STACK.lua"

# Make the vendored spack CLI available so `spack ...` / `pixi run spack ...` work.
case ":${PATH:-}:" in
  *":$SPACK_ROOT/bin:"*) : ;;
  *) export PATH="$SPACK_ROOT/bin${PATH:+:$PATH}" ;;
esac

# Put the generated modulefiles on MODULEPATH (idempotent) so `module load
# lfric-env/<variant>` resolves in any shell that sources this file. An end user
# with neither pixi nor this file just runs `module use $PREFIX/modulefiles` once.
case ":${MODULEPATH:-}:" in
  *":$MODULEFILES_DIR:"*) : ;;
  *) export MODULEPATH="$MODULEFILES_DIR${MODULEPATH:+:$MODULEPATH}" ;;
esac

# Spack 1.0 must run under Python < 3.12 (it uses ast.Str). Pin it to whatever
# python3 is on PATH now (pixi's 3.11, or a `module load`ed cray-python).
if [ -z "${SPACK_PYTHON:-}" ] && command -v python3 >/dev/null 2>&1; then
  SPACK_PYTHON="$(command -v python3)"; export SPACK_PYTHON
fi
