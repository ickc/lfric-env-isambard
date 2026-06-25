#!/usr/bin/env bash
# Common environment for the build/task scripts. SOURCE this file; do not run it.
#
# It sets up the Stage-1 BUILD context (where the vendored Spack lives, where the
# install tree goes, which variant is selected) AND puts the generated modulefiles
# on MODULEPATH so the Stage-1 product can be `module load`ed. It does NOT require
# pixi: pixi sources it via the activation hook, but `bash scripts/build.sh` (no
# pixi) sources it just the same — REPO_ROOT falls back from this file's path and
# SPACK_PYTHON from whatever python3 you brought (see build.sh's preflight).
#
# Kept deliberately side-effect-light (only env vars + PATH) because it is sourced
# on every `pixi run` via the activation hook. Anything heavy (module loads, spack
# queries) lives in build.sh instead.

# --- Repo root -------------------------------------------------------------
# pixi exports PIXI_PROJECT_ROOT; fall back to deriving it from this file.
if [ -n "${PIXI_PROJECT_ROOT:-}" ]; then
  REPO_ROOT="$PIXI_PROJECT_ROOT"
else
  REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")/.." && pwd)"
fi
export REPO_ROOT

# --- Vendored Spack (vendor/spack submodule) -------------------------------
export SPACK_ROOT="$REPO_ROOT/vendor/spack"

# --- Install prefix + build output -----------------------------------------
# PREFIX is where ALL Stage-1 build products live: the Spack install tree, the
# per-variant environment + its view, the generated modulefiles and the caches.
# It defaults OUTSIDE the repo — under the project space, namespaced by user and
# OS/arch — so that Stage 2 (just `module load lfric-env/<variant>`) never
# depends on the repo's location: once built, the repo can move or be deleted and
# the environment still loads. (Stage 1, the build itself, still needs the repo:
# the vendored Spack + pinned package repos live here.) Override with LFRIC_PREFIX.
#   PREFIX default: $PROJECTDIR/$USER/opt/<sysname>-<machine>  (e.g. Linux-aarch64)
_arch_tag="$(uname -sm | tr ' ' -)"
export PREFIX="${LFRIC_PREFIX:-${PROJECTDIR:-${SCRATCH:-$HOME}}/$USER/opt/$_arch_tag}"
unset _arch_tag
# WORKING_DIR is the directory all build output lands in; it defaults to PREFIX.
# LFRIC_WORKING_DIR still overrides it directly (kept for back-compat); set
# LFRIC_PREFIX to relocate the whole tree, LFRIC_WORKING_DIR for finer control.
export WORKING_DIR="${LFRIC_WORKING_DIR:-$PREFIX}"

# Redirect Spack's user config + cache under WORKING_DIR (i.e. PREFIX by default)
# so the build is hermetic: it neither reads nor writes the user's global ~/.spack.
export SPACK_USER_CONFIG_PATH="${SPACK_USER_CONFIG_PATH:-$WORKING_DIR/spack-config}"
export SPACK_USER_CACHE_PATH="${SPACK_USER_CACHE_PATH:-$WORKING_DIR/spack-cache}"

# --- Dependency stack variant (cray | spack) -------------------------------
# Two coexisting directory environments share one install tree (working_dir/opt):
#   cray  - system cray-mpich + Cray parallel HDF5/netCDF (externals)  [default]
#   spack - mpich + HDF5/netCDF built from source (portable fallback)
# LFRIC_STACK selects which one every pixi task operates on. Each variant lives
# in spack-env/<variant>/spack.yaml (both including ../common.yaml) with its own
# git-ignored .spack-env/ (view + lockfile) and its own generated Lmod modulefile
# working_dir/modulefiles/lfric-env/<variant>.lua. build.sh honours LFRIC_STACK
# for the module loads / solve assertions and writes that modulefile (via
# gen-modulefile.sh); activate.sh `module load`s the matching one — equivalently
# `module use working_dir/modulefiles && module load lfric-env/<variant>`.
# (Kept default-only here so this stays side-effect-light; build.sh validates the
# value.) The variant manifests are tracked; the generated state is not.
export LFRIC_STACK="${LFRIC_STACK:-cray}"
# The Spack directory environment is GENERATED under WORKING_DIR (so its view +
# lockfile land outside the repo, making Stage 2 repo-independent). The tracked
# manifest in the repo is the TEMPLATE build.sh instantiates from (rewriting its
# relative `include: ../common.yaml` to an absolute path back into the repo so
# the shared, version-controlled config + pinned repos are still used).
export SPACK_ENV_TEMPLATE="$REPO_ROOT/spack-env/$LFRIC_STACK/spack.yaml"
export SPACK_ENV_DIR="$WORKING_DIR/spack-env/$LFRIC_STACK"
export ENV_NAME="lfric-apps-isambard-$LFRIC_STACK"
# Lmod activation. MODULE_NAME is what you `module load`; MODULEFILE is the file
# that backs it and doubles as the "is this variant built?" sentinel (replaces
# the old env-runtime-<variant>.sh snippet check).
export MODULEFILES_DIR="$WORKING_DIR/modulefiles"
export MODULE_NAME="lfric-env/$LFRIC_STACK"
export MODULEFILE="$MODULEFILES_DIR/lfric-env/$LFRIC_STACK.lua"

# Make the vendored spack CLI available so `pixi run spack ...` just works.
case ":${PATH:-}:" in
  *":$SPACK_ROOT/bin:"*) : ;;
  *) export PATH="$SPACK_ROOT/bin${PATH:+:$PATH}" ;;
esac

# Put the generated modulefiles on MODULEPATH (idempotent), the same way we put
# the vendored spack on PATH above. This is why `module load lfric-env/<variant>`
# resolves in any shell that sources common.sh (pixi activation + the build
# scripts) — no imperative `module use` in activate.sh. An end user with neither
# pixi nor common.sh just runs `module use <repo>/working_dir/modulefiles` once.
case ":${MODULEPATH:-}:" in
  *":$MODULEFILES_DIR:"*) : ;;
  *) export MODULEPATH="$MODULEFILES_DIR${MODULEPATH:+:$MODULEPATH}" ;;
esac

# Spack 1.0 must run under Python < 3.12 (it uses ast.Str). Pin it to pixi's
# Python (3.11) so it is used regardless of what later module loads put on PATH.
if [ -z "${SPACK_PYTHON:-}" ] && command -v python3 >/dev/null 2>&1; then
  export SPACK_PYTHON="$(command -v python3)"
fi
