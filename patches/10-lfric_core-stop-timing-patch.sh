#!/usr/bin/env bash
# Auto-generated from install.sh. Target submodule: vendor/lfric_core
set -o pipefail
_here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="${PIXI_PROJECT_ROOT:-$(cd "$_here/.." && pwd)}"
WORKING_DIR="$REPO_ROOT/vendor"
info() { echo "INFO: $*"; }
warn() { echo "WARN: $*" >&2; }
fail() { echo "ERROR: $*" >&2; return 1; }

patch_stop_timing_signature() {
  local timing_file="$WORKING_DIR/lfric_core/infrastructure/source/utilities/timing_mod.F90"
  if [ ! -f "$timing_file" ]; then
    warn "timing_mod.F90 not found at $timing_file; skipping stop_timing patch."
    return 0
  fi
  if grep -q "optional :: timing_section_name" "$timing_file"; then
    return 0
  fi
  if ! perl -0777 -i -pe 's/subroutine stop_timing\(\s*timing_section_handle\s*\)\s*\n\s*implicit none\s*\n\s*integer\(tik\),\s*intent\(in\)\s*::\s*timing_section_handle/subroutine stop_timing( timing_section_handle, timing_section_name )\n\n        implicit none\n\n        integer(tik),  intent(in) :: timing_section_handle\n        character(*),  intent(in), optional :: timing_section_name/s' "$timing_file"; then
    warn "Failed to patch stop_timing signature in $timing_file."
    return 0
  fi
  info "Patched stop_timing signature for compatibility."
  return 0
}

patch_stop_timing_signature
exit $?
