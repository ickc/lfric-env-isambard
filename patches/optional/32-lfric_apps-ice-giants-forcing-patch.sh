#!/usr/bin/env bash
# Target: an EXTRACTED lfric_apps tree at $LFRIC_SRC_ROOT/lfric_apps (2026.07.1 /
# vn3.2). OPT-IN — see patches/optional/README.md. Nothing applies this
# automatically; u-dt000's `extract` task invokes it by path.
#
# WHAT IT IS
#
#   dennissergeev/lfric_apps@ice_giants_tf, forward-ported from vn3.0 to the vn3.2
#   this environment builds.
#
# u-dt000's science is `theta_forcing='ice_giants_obs_like'` (Uranus/Neptune
# temperature + wind forcing). That forcing exists in exactly one place — Denis
# Sergeev's branch
#
#   https://github.com/dennissergeev/lfric_apps/tree/ice_giants_tf   (b57ddcc9)
#
# and nowhere in MetOffice mainline, at any tag. The branch is still based on
# vn3.0 and he has not had time to upgrade it, which is why this repo carries the
# forward-port rather than pointing `dependencies.yaml` straight at the branch.
#
# Two commits of his are science, and they are what this patch carries:
#
#   b57ddcc9  add ice giants temperature and wind forcing
#   1d4b42b8  add temperature forcing parameters to rose meta
#
# (`5a2bb7ee` / `96b327b7`, the extract_source error handling, are already in
# mainline at 2026.07.1 and are not carried.) Five files, ~310 lines:
#
#   science/gungho/rose-meta/lfric-gungho/HEAD/rose-meta.conf
#       + the `ice_giants_obs_like` value of namelist:external_forcing=theta_forcing
#       + three new COMPULSORY items: theta_relax_time_scale, wind_relax_time_scale,
#         held_suarez_sigma_b
#   science/gungho/source/algorithm/physics/external_forcing_alg_mod.X90
#       + the ice_giants_kernel_type invoke for that case
#   science/gungho/source/kernel/external_forcing/ice_giants_forcings_mod.F90   (new)
#   science/gungho/source/kernel/external_forcing/ice_giants_kernel_mod.F90     (new)
#   science/gungho/source/kernel/external_forcing/held_suarez_forcings_mod.F90
#       SIGMA_B and the KF/KA/KS relaxation rates stop being hardcoded `parameter`s
#       and come from the namelist instead. THIS is what u-dt000 tripped over for so
#       long: it sets `held_suarez_sigma_b`, and every mainline LFRic answers
#       "Cannot match namelist object name held_suarez_sigma_b" because there the
#       name is a Fortran parameter, not a namelist field.
#
# WHY IT IS OPT-IN, NOT PART OF THE STACK
#
# Those three rose-meta items are `compulsory=true`, so once the metadata carries
# them EVERY gungho app config must set them or the model aborts reading its
# namelists. u-dr932 and u-dn704 do not set them. So this cannot live in
# patches/ proper — see patches/optional/README.md.
#
# REGENERATING IT (the one manual step is small and worth re-checking on a bump)
#
#   git -C vendor/lfric_apps remote add dennis https://github.com/dennissergeev/lfric_apps.git
#   git -C vendor/lfric_apps fetch dennis ice_giants_tf:refs/remotes/dennis/ice_giants_tf
#   git -C vendor/lfric_apps checkout -B ice-giants-vn3.2 <the 2026.07.1 commit>
#   git -C vendor/lfric_apps merge dennis/ice_giants_tf
#
# One conflict, in rose-meta.conf, both hunks a collision between mainline's newer
# 'nudging' option and Denis' 'ice_giants_obs_like' — resolved as the UNION:
# `ice_giants_obs_like` inserted after `deep_hot_jupiter` (where he put it) with
# `nudging` kept last (where mainline has it), and his `held_suarez_sigma_b`
# trigger appended to mainline's `wind_forcing` trigger list. Then
#
#   git -C vendor/lfric_apps diff <the 2026.07.1 commit> HEAD \
#       > patches/optional/32-lfric_apps-ice-giants-forcing.patch
#
# UPSTREAMING
#
# The fix for all of this is Denis rebasing `ice_giants_tf` onto a current LFRic
# and the forcing going to MetOffice mainline, at which point this patch is deleted
# and u-dt000's dependencies.yaml names his branch (or the tag) directly. The
# .patch file next to this script is exactly the diff to hand him.
#
# Idempotent: re-running is a no-op.
set -o pipefail
_here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="${PIXI_PROJECT_ROOT:-$(cd "$_here/../.." && pwd)}"
# The env build + minimal-compile example patch the vendored trees in place; the
# science-suites' extract sets LFRIC_SRC_ROOT to a per-suite extracted tree so the
# same patch applies there.
WORKING_DIR="${LFRIC_SRC_ROOT:-$REPO_ROOT/vendor}"

APPS_ROOT="$WORKING_DIR/lfric_apps"
PATCH_FILE="$_here/32-lfric_apps-ice-giants-forcing.patch"

info() { echo "INFO: $*"; }
warn() { echo "WARN: $*" >&2; }
fail() { echo "ERROR: $*" >&2; }

if [ ! -d "$APPS_ROOT" ]; then
  warn "no lfric_apps tree at $APPS_ROOT; skipping the ice-giants forcing patch."
  exit 0
fi
[ -f "$PATCH_FILE" ] || { fail "patch missing: $PATCH_FILE"; exit 1; }

# The extracted tree is a git clone (merge_sources.py clones it), so use git apply
# -- it gives us both the already-applied test and a dry run.
if git -C "$APPS_ROOT" apply --reverse --check -p1 "$PATCH_FILE" >/dev/null 2>&1; then
  info "ice-giants forcing already present in $APPS_ROOT."
  exit 0
fi
if ! git -C "$APPS_ROOT" apply --check -p1 "$PATCH_FILE" >/dev/null 2>&1; then
  fail "the ice-giants forcing patch does not apply to $APPS_ROOT."
  fail "  Most likely lfric_apps has moved off 2026.07.1 (vn3.2), which this patch"
  fail "  was forward-ported against. Regenerate it -- the recipe is in the header"
  fail "  of this script."
  exit 1
fi
git -C "$APPS_ROOT" apply -p1 "$PATCH_FILE" || { fail "git apply failed"; exit 1; }
info "Applied dennissergeev/lfric_apps@ice_giants_tf (forward-ported to vn3.2)."
