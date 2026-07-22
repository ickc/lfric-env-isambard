#!/usr/bin/env bash
# Target submodule: vendor/lfric_apps  (LFRic Apps 2026.07.1 / vn3.2)
#
# Fix an upstream 2026.07.1 regression that breaks any "dynamics + external
# forcing only" configuration (all UM physics sections = 'none'), e.g. the
# u-dr932 / u-dt000 science-suite examples:
#
#   ERROR: get_field: No 64-bit field [dtheta_mphys] in field collection:
#          microphysics_fields
#
# What changed: vn3.2 wrapped the whole UM_PHYSICS field-creation block in
# create_physics_prognostics_mod.F90 in a new guard
#
#   if ( surface            /= surface_none            .or. &
#        radiation          /= radiation_none          .or. &
#        orographic_drag    /= orographic_drag_none    .or. &
#        stochastic_physics /= stochastic_physics_none .or. &
#        boundary_layer     /= boundary_layer_none ) then
#
# so with every one of those 'none' the microphysics increment fields
# (dtheta_mphys, dmv_mphys, ...) are no longer created. But slow_physics_alg_mod
# still fetches dtheta_mphys UNCONDITIONALLY, before the
# `if ( microphysics == microphysics_um ... )` block that is the only thing
# which actually uses it. Every later use is already gated on
# `microphysics_done`, so the fetch is the only unguarded reference.
#
# That the new guard omits `microphysics` while the same commit added now-unused
# `microphysics` / `microphysics_none` imports to that module suggests the
# omission is an upstream oversight. Adding microphysics to the *creation* guard
# would not help these suites anyway (their microphysics is inactive too), so
# fix the consumer: move the fetch inside the block that uses it.
#
# Report upstream; drop this patch once 2026.07.x carries a fix.
set -o pipefail
_here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="${PIXI_PROJECT_ROOT:-$(cd "$_here/.." && pwd)}"
# The env build + minimal-compile example patch the vendored trees in place; the
# science-suites' offline extract sets LFRIC_SRC_ROOT to a per-suite extracted tree
# so the same patch applies there.
WORKING_DIR="${LFRIC_SRC_ROOT:-$REPO_ROOT/vendor}"
info() { echo "INFO: $*"; }
warn() { echo "WARN: $*" >&2; }
fail() { echo "ERROR: $*" >&2; }

patch_slow_physics_mphys_field() {
  local alg="$WORKING_DIR/lfric_apps/science/gungho/source/algorithm/physics/slow_physics_alg_mod.X90"
  if [ ! -f "$alg" ]; then
    warn "slow_physics_alg_mod.X90 not found at $alg; skipping mphys field patch."
    return 0
  fi
  if grep -q "LFRIC-ENV-ISAMBARD: dtheta_mphys fetched only when microphysics runs" "$alg"; then
    return 0
  fi

  ALG="$alg" python3 - <<'PYEOF' || { fail "failed to patch slow_physics_alg_mod.X90"; return 1; }
import os
import re
import sys

path = os.environ["ALG"]
with open(path) as fh:
    src = fh.read()

fetch = "    call microphysics_fields%get_field('dtheta_mphys', dtheta_mphys)\n"
if fetch not in src:
    sys.exit("expected unguarded get_field('dtheta_mphys') not found")

# Drop the unguarded fetch. clone_bundle/set_bundle_scalar on the LOCAL
# dmr_mphys must stay put: dmr_mphys is passed on unconditionally later.
src = src.replace(fetch, "", 1)

# Re-insert it as the first statement inside the microphysics block.
guard = re.search(
    r"( *)if \( microphysics == microphysics_um \.and\. *&\n"
    r" *microphysics_placement == microphysics_placement_slow\) then\n",
    src,
)
if not guard:
    sys.exit("microphysics_um guard not found")

indent = guard.group(1)
insert = (
    f"{indent}  ! LFRIC-ENV-ISAMBARD: dtheta_mphys fetched only when microphysics runs.\n"
    f"{indent}  ! vn3.2 stopped creating the UM-physics fields when every section in the\n"
    f"{indent}  ! create_physics_prognostics guard is 'none', but left this fetch\n"
    f"{indent}  ! unguarded, so idealised (forcing-only) configs died here.\n"
    f"{indent}  call microphysics_fields%get_field('dtheta_mphys', dtheta_mphys)\n"
)
src = src[: guard.end()] + insert + src[guard.end() :]

with open(path, "w") as fh:
    fh.write(src)
print("INFO: Patched slow_physics_alg_mod.X90 dtheta_mphys fetch.")
PYEOF
}

patch_slow_physics_mphys_field
exit $?
