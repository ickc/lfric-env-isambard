#!/usr/bin/env bash
# Common environment for every pixi task. SOURCE this file; do not execute it.
#
# Kept deliberately side-effect-light (only env vars + PATH) because it is
# sourced on every `pixi run` via the activation hook (scripts/activate.sh).
# Anything heavy (module loads, spack queries) lives in build.sh instead.

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

# --- Repo-local build output (git-ignored via /working_dir/) ---------------
# Override with LFRIC_WORKING_DIR to put the heavy install tree elsewhere.
export WORKING_DIR="${LFRIC_WORKING_DIR:-$REPO_ROOT/working_dir}"

# Redirect Spack's user config + cache into the repo-local working dir so the
# build is hermetic: it neither reads nor writes the user's global ~/.spack.
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
export SPACK_ENV_DIR="$REPO_ROOT/spack-env/$LFRIC_STACK"
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
