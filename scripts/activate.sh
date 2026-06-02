#!/usr/bin/env bash
# Auto-activation of the built LFRic Spack environment.
#
# Sourced by pixi on every `pixi run` / `pixi shell` (see [activation] in
# pixi.toml) and usable directly. It is a deliberate NO-OP until the
# environment has been built, so `pixi run build` works on a clean checkout.
#
# The expensive parts (resolving package prefixes) are precomputed once by
# build.sh into working_dir/env-runtime.sh, so activation stays fast.

_act_here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=scripts/common.sh
. "$_act_here/common.sh"

# env-runtime.sh is written by build.sh only after a successful build.
if [ -f "$WORKING_DIR/env-runtime.sh" ] && [ -f "$SPACK_ROOT/share/spack/setup-env.sh" ]; then
  # shellcheck source=/dev/null
  . "$SPACK_ROOT/share/spack/setup-env.sh" 2>/dev/null || true
  spack env activate -d "$SPACK_ENV_DIR" 2>/dev/null || true
  # shellcheck source=/dev/null
  . "$WORKING_DIR/env-runtime.sh" 2>/dev/null || true
fi
