#!/usr/bin/env bash
# build.sh — build the environment. `pixi run build` (or build-spack).
#
# Run this on a COMPUTE node, via build.sbatch. A full build forks thousands of
# processes and the login nodes cap you at ~900 (`ulimit -u`), so it will fail
# there with "fork: Resource temporarily unavailable".
#
# Everything it produces lands under $LFRIC_PREFIX, outside the repo. Re-runs
# are cheap: Spack's store is content-addressed, so already-built packages are
# skipped and only what changed is rebuilt.
#
# The product is the modulefile that lfric_gen_modulefile writes; lfric_smoke_test
# then loads it the way an end user will, which is the real acceptance test.
set -uo pipefail
# Re-source the configuration in this process, so an inline override such as
# `LFRIC_STACK=spack bash build.sh` re-derives every path that depends on it.
cd -- "$(dirname -- "${BASH_SOURCE[0]}")" || exit 1
. ./env.sh || exit 1
. ./lib.sh

lfric_prepare           # python, submodules, patches, Cray modules, spack, config
lfric_concretize        # the solve, plus the variant assertions
lfric_install           # libxml2 -> yaxt -> heavy packages -> everything
lfric_regenerate_view
lfric_gen_modulefile
lfric_smoke_test

echo ""
echo "BUILD_OK — $LFRIC_ENV_VERSION / $LFRIC_STACK"
echo "Use it:  module use $MODULEFILES_DIR"
echo "         module load $MODULE_NAME"
