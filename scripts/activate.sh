#!/usr/bin/env bash
# Auto-activation of the built LFRic Spack environment.
#
# Sourced by pixi on every `pixi run` / `pixi shell` (see [activation] in
# pixi.toml) and usable directly. It is a deliberate NO-OP until the
# environment has been built, so `pixi run build` works on a clean checkout.
#
# We intentionally do NOT source spack's setup-env.sh or call `spack env
# activate` here: those export bash shell functions (spack, _spack_shell_wrapper)
# that error noisily when pixi runs a command under /bin/sh. Everything we need
# is achieved without them:
#   - SPACK_ENV=<dir>           makes `pixi run spack ...` operate on this env
#   - $ENV_RUNTIME (working_dir/env-runtime-<variant>.sh) puts the view
#     (rose/cylc/psyclone/...) on PATH and sets SHUMLIB/FC/LD_* (precomputed once
#     by build.sh per LFRIC_STACK variant, so this is fast)
# The vendored `spack` binary is already on PATH via common.sh.

_act_here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=scripts/common.sh
. "$_act_here/common.sh"

if [ -f "$ENV_RUNTIME" ]; then
  export SPACK_ENV="$SPACK_ENV_DIR"
  # shellcheck source=/dev/null
  . "$ENV_RUNTIME" 2>/dev/null || true
fi
