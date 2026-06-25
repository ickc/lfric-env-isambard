#!/usr/bin/env bash
# fetch.sh — pre-download every Stage-1 source on the LOGIN NODE.
#
# Runs the network/I/O-heavy work on a login node so the compute-node build stays
# offline: clone the pinned Stage-1 submodules (if missing), concretize the
# selected variant, then `spack fetch` every from-source package (xios, mpich,
# hdf5, ...) into the persistent source cache ($PREFIX/source-cache). The
# subsequent scripts/build.sh then installs from a warm cache and fetches nothing
# — which also sidesteps the intermittent gitlab.in2p3.fr clone failure the XIOS
# verification step warns about.
#
# Shares the prepare + concretize phases with build.sh (scripts/lib.sh), so the
# solve here is exactly the one the build uses. Run on a LOGIN NODE; concurrency
# is capped (FETCH_JOBS, default 4) for the login node's small `ulimit -u`.
# Repeat with LFRIC_STACK=spack to warm the from-source variant's sources too.
set -uo pipefail

_here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=scripts/common.sh
. "$_here/common.sh"
# shellcheck source=scripts/lib.sh
. "$_here/lib.sh"

# Single concurrency knob. Small by default: this runs on a login node whose
# `ulimit -u` is low (~950 on Isambard 3), and submodule clones fork freely.
FETCH_JOBS="${FETCH_JOBS:-4}"

# Cap git's submodule fetch concurrency for this whole process tree — including
# any submodule clones Spack itself performs while fetching — so a --recursive
# clone cannot fan out past FETCH_JOBS at any nesting level and trip the login
# node's `ulimit -u`. Injected via GIT_CONFIG_* (git >= 2.31) so it reaches every
# `git` we spawn, directly or through Spack, not just our own command line (a bare
# `--jobs` flag does not reliably propagate to recursive sub-levels).
_gc_n="${GIT_CONFIG_COUNT:-0}"
export "GIT_CONFIG_KEY_${_gc_n}=submodule.fetchJobs"
export "GIT_CONFIG_VALUE_${_gc_n}=$FETCH_JOBS"
export GIT_CONFIG_COUNT="$((_gc_n + 1))"

info "LFRIC_STACK=$LFRIC_STACK  FETCH_JOBS=$FETCH_JOBS (login-node ulimit -u cap)"

lfric_clone_missing_submodules "$FETCH_JOBS"  # fetch is self-sufficient: clone if absent
lfric_prepare                                 # validate + python + patches + modules + env
lfric_concretize                              # same solve the build uses
lfric_fetch                                   # download all sources into the cache

echo "FETCH_OK"
