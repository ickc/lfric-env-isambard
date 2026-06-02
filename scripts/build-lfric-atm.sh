#!/usr/bin/env bash
# build-lfric-atm.sh — compile lfric_atm and run its example.
#
# Separate from `build` because this step clones private Met Office physics
# repos (casim, jules, socrates) over SSH during the build. You need a running
# SSH agent whose key is authorized for those repos. The Spack environment from
# `pixi run build` is complete and usable without this step.
set -uo pipefail

_here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=scripts/activate.sh
. "$_here/activate.sh"

info() { echo "INFO: $*"; }
warn() { echo "WARN: $*" >&2; }
die()  { echo "ERROR: $*" >&2; exit 1; }

[ -f "$WORKING_DIR/env-runtime.sh" ] || die "Environment not built. Run: pixi run build"

# Accept new host keys non-interactively for the physics-repo clones.
export GIT_SSH_COMMAND="${GIT_SSH_COMMAND:-ssh -o StrictHostKeyChecking=accept-new -o BatchMode=yes}"

# Load GCC 12.3 for the compile (same as build.sh).
GCC_MODULE="${GCC_MODULE:-gcc-native/12.3}"
if ! command -v module >/dev/null 2>&1; then
  for f in /etc/profile.d/lmod.sh /etc/profile.d/modules.sh \
           /usr/share/lmod/lmod/init/bash /opt/cray/pe/lmod/lmod/init/bash; do
    # shellcheck source=/dev/null
    [ -f "$f" ] && . "$f" && break
  done
fi
command -v module >/dev/null 2>&1 && module load "$GCC_MODULE" 2>/dev/null || true

APPS_ROOT_DIR="${APPS_ROOT_DIR:-$REPO_ROOT/vendor/lfric_apps}"
CORE_ROOT_DIR="${CORE_ROOT_DIR:-$REPO_ROOT/vendor/lfric_core}"
LFRIC_TARGET_PLATFORM="${LFRIC_TARGET_PLATFORM:-meto-spice}"
MAKE_JOBS="${MAKE_JOBS:-8}"
PROJECT="${PROJECT:-lfric_atm}"

# local_build.py invokes `python`; ensure one exists on PATH.
PYTHON_BIN="${PYTHON:-}"
if [ -z "$PYTHON_BIN" ]; then
  if command -v python >/dev/null 2>&1; then PYTHON_BIN=python
  elif command -v python3 >/dev/null 2>&1; then
    _tmp_py="$(mktemp -d)"; ln -sf "$(command -v python3)" "$_tmp_py/python"
    export PATH="$_tmp_py:$PATH"; PYTHON_BIN=python
  else die "no python on PATH"; fi
fi

[ -f "$APPS_ROOT_DIR/build/local_build.py" ] || die "local_build.py not found in $APPS_ROOT_DIR/build"

if [ "${CLEAN_PHYSICS_SCRATCH:-1}" != "0" ]; then
  rm -rf "$APPS_ROOT_DIR/applications/lfric_atm/physics_scratch" \
         "$APPS_ROOT_DIR/applications/lfric_atm/working/physics_scratch"
fi

LOCAL_BUILD_WORKING_DIR="$APPS_ROOT_DIR/applications/lfric_atm/working"
LOCAL_BUILD_LOG="$WORKING_DIR/lfric_atm-make.log"
[ "${CLEAN_BUILD_WORKING:-1}" != "0" ] && rm -rf "$LOCAL_BUILD_WORKING_DIR/build_lfric_atm"

build_once() {
  local with_target="$1"
  local cmd=(
    "$PYTHON_BIN" "$APPS_ROOT_DIR/build/local_build.py" lfric_atm
    -c "$CORE_ROOT_DIR" -w "$LOCAL_BUILD_WORKING_DIR" -j "$MAKE_JOBS" -t build
  )
  [ "$with_target" = "1" ] && cmd+=(-u "$LFRIC_TARGET_PLATFORM")
  [ "${VERBOSE_BUILD:-0}" = "1" ] && cmd+=(-v)
  ( cd "$APPS_ROOT_DIR" && "${cmd[@]}" ) |& tee "$LOCAL_BUILD_LOG"
  return "${PIPESTATUS[0]}"
}

added_target=1
help_txt="$("$PYTHON_BIN" "$APPS_ROOT_DIR/build/local_build.py" -h 2>&1 || true)"
printf '%s\n' "$help_txt" | grep -qE '(^|[[:space:]])-u([[:space:],]|$)|--target' || added_target=0

info "Building lfric_atm (target platform: $LFRIC_TARGET_PLATFORM, -u included: $added_target)"
build_once "$added_target"
status=$?
if [ "$status" -ne 0 ] && [ "$added_target" -eq 1 ] && grep -q "unrecognized arguments: -u" "$LOCAL_BUILD_LOG"; then
  warn "local_build.py rejected -u; retrying without target platform"
  build_once 0; status=$?
fi
[ "$status" -eq 0 ] || die "local_build.py failed for lfric_atm (exit $status). See $LOCAL_BUILD_LOG"

APP_BIN="$APPS_ROOT_DIR/applications/$PROJECT/bin/$PROJECT"
[ -x "$APP_BIN" ] || die "Executable not found at $APP_BIN"
info "Built: $APP_BIN"

EXAMPLE_DIR="$APPS_ROOT_DIR/applications/$PROJECT/example"
if [ -d "$EXAMPLE_DIR" ] && [ -f "$EXAMPLE_DIR/configuration.nml" ]; then
  info "Running example in $EXAMPLE_DIR"
  ( cd "$EXAMPLE_DIR" && "$APP_BIN" configuration.nml )
else
  warn "example configuration not found under $EXAMPLE_DIR; run $APP_BIN manually."
fi
echo "LFRIC_ATM_OK"
