#!/usr/bin/env bash
# Target: an EXTRACTED lfric_apps tree at $LFRIC_SRC_ROOT/lfric_apps (2026.07.1 /
# vn3.2). OPT-IN — see patches/optional/README.md. Nothing applies this
# automatically; u-dz791's `extract` task invokes it by path.
#
# WHAT IT IS
#
#   Two of Alex Corbett's lfric_apps branches, merged and forward-ported from 2026.03.1
#   (vn3.1) to the 2026.07.1 (vn3.2) this environment builds:
#
#     https://github.com/corbopy/lfric_apps/tree/vn3.1-feat/t-and-rh-init-clean  (299860b3)
#     https://github.com/corbopy/lfric_apps/tree/qsaturation-use-epsilon         (6a5c342c)
#
# u-dz791 (the training course's idealised hydrogen-atmosphere CRM) declares both in its
# dependencies.yaml, from a clone on a Met Office machine; these are the public copies.
# They are its science, and none of it is in MetOffice mainline at any tag:
#
#   t-and-rh-init-clean   `profile_variable` in namelist:initial_temperature
#                         ('potential'|'absolute') and namelist:initial_vapour
#                         ('mr'|'rh'), and a new vert_balance_kernel that builds a
#                         hydrostatically balanced theta/mr/exner from absolute T or RH.
#                         u-dz791 initialises with profile_variable='absolute' -- the
#                         "corrected" isothermal start the practicals refer to.
#   qsaturation-use-epsilon  physics_common_mod's qsat uses epsilon (Rd/Rv) rather than
#                         the Earth-air constant, so it is right for an H2 atmosphere.
#
# Five files, ~600 lines:
#
#   science/gungho/rose-meta/lfric-gungho/HEAD/rose-meta.conf     the two profile_variable items
#   science/gungho/source/algorithm/initialisation/init_thermo_profile_alg_mod.x90
#   science/gungho/source/driver/gungho_init_prognostics_driver_mod.f90   (+ exner argument)
#   science/gungho/source/kernel/initialisation/vert_balance_kernel_mod.F90   (new)
#   science/gungho/source/physics/physics_common_mod.f90
#
# Not carried: the branches' unit-test, rose-stem, KGO and example-namelist changes,
# none of which a suite build reads, and the `vn3.1_t226` upgrade macro in versions.py,
# which only adds default `profile_variable` values that u-dz791's configs already set.
#
# WHY IT IS OPT-IN, NOT PART OF THE STACK
#
# Both new rose-meta items are `compulsory=true`, and init_thermo_profile_alg now always
# takes mr_v and exner. A science change to the initialisation of every
# `test='specified_profiles'` configuration is not something the shared stack may impose
# on suites that did not ask for it.
#
# REGENERATING IT
#
#   git -C vendor/lfric_apps fetch https://github.com/corbopy/lfric_apps.git \
#       vn3.1-feat/t-and-rh-init-clean:refs/remotes/corbopy/t-and-rh-init-clean \
#       qsaturation-use-epsilon:refs/remotes/corbopy/qsaturation-use-epsilon
#   git -C vendor/lfric_apps checkout -B dz791-vn3.2 2026.07.1
#   git -C vendor/lfric_apps merge corbopy/t-and-rh-init-clean
#
# 1. Conflicts. Two source files, all of it API drift between 2026.03.1 and 2026.07.1
#    rather than science: mainline now passes `config` and a `mesh` pointer where the
#    branch has `mesh_id`, and the branch adds `exner`, `W3` heights and the
#    profile_variable imports. Resolve as the union: 2026.07.1's call forms, the
#    branch's new arguments --
#      init_thermo_profile_alg( config, theta, mr(imr_v), exner )
#      get_height_fe(config, mesh, W3) / get_height_fv(config, mesh, W3)
#    rose-meta.conf conflicts where mainline added the theta_pert_* items next to
#    the branch's profile_variable: keep both. For CONTRIBUTORS.md, versions.py and the
#    unit tests take 2026.07.1's (`git checkout 2026.07.1 -- <file>`).
# 2. `git merge corbopy/qsaturation-use-epsilon` -- clean.
# 3. git diff 2026.07.1 HEAD -- science ':!*unit-test*' > patches/optional/33-lfric_apps-dz791-profile-init.patch
#
# When Alex's branches are rebased onto a current LFRic (or reach mainline), u-dz791's
# dependencies.yaml goes back to declaring them and this patch is deleted.
set -o pipefail
_here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="${PIXI_PROJECT_ROOT:-$(cd "$_here/../.." && pwd)}"
WORKING_DIR="${LFRIC_SRC_ROOT:-$REPO_ROOT/vendor}"

APPS_ROOT="$WORKING_DIR/lfric_apps"
PATCH_FILE="$_here/33-lfric_apps-dz791-profile-init.patch"

info() { echo "INFO: $*"; }
warn() { echo "WARN: $*" >&2; }
fail() { echo "ERROR: $*" >&2; }

if [ ! -d "$APPS_ROOT" ]; then
  warn "no lfric_apps tree at $APPS_ROOT; skipping the u-dz791 profile-init patch."
  exit 0
fi
[ -f "$PATCH_FILE" ] || { fail "patch missing: $PATCH_FILE"; exit 1; }

if git -C "$APPS_ROOT" apply --reverse --check -p1 "$PATCH_FILE" >/dev/null 2>&1; then
  info "u-dz791 profile-init science already present in $APPS_ROOT."
  exit 0
fi
if ! git -C "$APPS_ROOT" apply --check -p1 "$PATCH_FILE" >/dev/null 2>&1; then
  fail "the u-dz791 profile-init patch does not apply to $APPS_ROOT."
  fail "  Most likely lfric_apps has moved off 2026.07.1 (vn3.2), which this patch"
  fail "  was forward-ported against. Regenerate it -- the recipe is in the header"
  fail "  of this script."
  exit 1
fi
git -C "$APPS_ROOT" apply -p1 "$PATCH_FILE" || { fail "git apply failed"; exit 1; }
info "Applied corbopy/lfric_apps t-and-rh-init-clean + qsaturation-use-epsilon (forward-ported to vn3.2)."
