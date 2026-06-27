#!/usr/bin/env bash
# build.sh — build the LFRic Apps Spack environment (Stage 1).
#
# Produces a complete, activatable Spack environment (rose, cylc, psyclone, xios,
# mpich, ...) and its Lmod modulefile under PREFIX. It does NOT compile lfric_atm
# (that needs the private physics repos and is the minimal-compile example in
# examples/minimal-compile/).
#
# The phases live in scripts/lib.sh; this driver just composes them in order:
# prepare + concretize (the SOLVE — also a standalone step, scripts/concretize.sh)
# then install + view + modulefile + smoke test. All heavy output goes under
# PREFIX (outside the repo); re-runs are cheap (Spack skips already-built,
# content-addressed packages). Run on a compute node — see scripts/build.sbatch.
set -uo pipefail

_here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=scripts/common.sh
. "$_here/common.sh"
# shellcheck source=scripts/lib.sh
. "$_here/lib.sh"

lfric_prepare          # validate + python + submodules + patches + modules + env
lfric_verify_xios      # non-fatal upstream XIOS source check
lfric_concretize       # the dependency solve + variant assertions
lfric_install          # libxml2 -> yaxt -> heavy pkgs -> full environment
lfric_regenerate_view
lfric_gen_modulefile
lfric_smoke_test

echo ""
echo "BUILD_OK — environment built ($LFRIC_STACK variant)."
echo "Use it:  module use $MODULEFILES_DIR && module load $MODULE_NAME"
echo "                   (inside pixi: any 'pixi run ...' auto-loads it)"
