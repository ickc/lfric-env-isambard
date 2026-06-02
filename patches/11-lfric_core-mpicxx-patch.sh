#!/usr/bin/env bash
# Auto-generated from install.sh. Target submodule: vendor/lfric_core
set -o pipefail
_here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="${PIXI_PROJECT_ROOT:-$(cd "$_here/.." && pwd)}"
WORKING_DIR="$REPO_ROOT/vendor"
info() { echo "INFO: $*"; }
warn() { echo "WARN: $*" >&2; }
fail() { echo "ERROR: $*" >&2; return 1; }

patch_mpicxx_wrapper_detection() {
  local mpicxx_mk="$WORKING_DIR/lfric_core/infrastructure/build/cxx/mpic++.mk"
  if [ ! -f "$mpicxx_mk" ]; then
    warn "mpic++.mk not found at $mpicxx_mk; skipping wrapper patch."
    return 0
  fi
  if grep -q "Normalise wrapper output" "$mpicxx_mk"; then
    return 0
  fi
  cat > "$mpicxx_mk" <<'EOF'
##############################################################################
# (c) Crown copyright 2024 Met Office. All rights reserved.
# The file LICENCE, distributed with this code, contains details of the terms
# under which the code may be used.
##############################################################################

MPIC_COMPILER := $(shell $(CXX) --version                    | awk -F " " 'NR<2 { printf "%s", $$1 }')

# Normalise wrapper output to known compiler ids.
ifneq (,$(findstring g++, $(MPIC_COMPILER)))
  MPIC_COMPILER := g++
endif
ifneq (,$(findstring nvc++, $(MPIC_COMPILER)))
  MPIC_COMPILER := nvc++
endif
ifeq ($(MPIC_COMPILER),PIC_COMPILER)
  MPIC_COMPILER := g++
endif

$(info ** Chosen MPI C++ compiler "$(MPIC_COMPILER)")

ifeq '$(MPIC_COMPILER)' 'g++'
  CXX_COMPILER = g++
else ifeq '$(MPIC_COMPILER)' 'icc'
  CXX_COMPILER = icc
else ifeq '$(MPIC_COMPILER)' 'Cray'
  CXX_COMPILER = craycc
else ifeq '$(MPIC_COMPILER)' 'nvc++'
  CXX_COMPILER = nvc++
else
  $(error Unrecognised mpic++ compiler option: "$(MPIC_COMPILER)")
endif

include $(LFRIC_BUILD)/cxx/$(CXX_COMPILER).mk
EOF
  info "Patched mpic++.mk wrapper detection."
  return 0
}

patch_mpicxx_wrapper_detection
exit $?
