#!/usr/bin/env bash
# concretize.sh — solve the dependency graph, and assert the solution matches
# the requested variant. `pixi run concretize` (or concretize-spack).
#
# This is the cheap check. It runs on a login node in about a minute, needs no
# Slurm allocation, and catches every class of mistake a manifest change can
# make: an unsatisfiable constraint, an external that stopped resolving, a
# provider that silently swapped. Run it after touching spack-env/ or
# spack-repo/ and before spending hours of compute on the install.
#
# Idempotent — a no-op when the lock already matches the manifest. Set
# FORCE_CONCRETIZE=1 to force a fresh re-solve.
set -uo pipefail
# Re-source the configuration in this process, so an inline override such as
# `LFRIC_STACK=spack bash build.sh` re-derives every path that depends on it.
cd -- "$(dirname -- "${BASH_SOURCE[0]}")" || exit 1
. ./env.sh || exit 1
. ./lib.sh

lfric_prepare
lfric_concretize

echo "CONCRETIZE_OK"
