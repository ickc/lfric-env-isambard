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

# Directory (anonymous) Spack environment. spack-env/spack.yaml is tracked; the
# generated spack-env/.spack-env/ (view + lockfile) is git-ignored.
export SPACK_ENV_DIR="$REPO_ROOT/spack-env"
export ENV_NAME="lfric-apps-isambard"

# Make the vendored spack CLI available so `pixi run spack ...` just works.
case ":${PATH:-}:" in
  *":$SPACK_ROOT/bin:"*) : ;;
  *) export PATH="$SPACK_ROOT/bin${PATH:+:$PATH}" ;;
esac

# Spack 1.0 must run under Python < 3.12 (it uses ast.Str). Pin it to pixi's
# Python (3.11) so it is used regardless of what later module loads put on PATH.
if [ -z "${SPACK_PYTHON:-}" ] && command -v python3 >/dev/null 2>&1; then
  export SPACK_PYTHON="$(command -v python3)"
fi
