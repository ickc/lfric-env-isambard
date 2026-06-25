#!/usr/bin/env bash
# fetch.sh — pre-download every Stage-1 source on the LOGIN NODE.
#
# Splits build.sh at the concretize boundary so the network/I/O-heavy work runs
# on a login node and the compute-node build stays offline:
#   1. ensure the pinned Stage-1 submodules are present (clone if missing);
#   2. concretize the selected variant (delegated to build.sh — no duplication);
#   3. `spack fetch` every from-source package (xios, mpich, hdf5, ...) into the
#      persistent source cache ($PREFIX/source-cache).
# The subsequent `scripts/build.sh` (compute node, via build.sbatch) then installs
# from a warm cache and performs no fetching — which also sidesteps the
# intermittent gitlab.in2p3.fr clone failure the XIOS verification step warns about.
#
# Run this on a LOGIN NODE (network + I/O live). Concurrency is capped via
# FETCH_JOBS (default 4) because login nodes have a small `ulimit -u`: an uncapped
# recursive submodule clone can exhaust it and die with "fork: Resource
# temporarily unavailable". `spack fetch` itself is sequential across packages.
#
# Repeat with LFRIC_STACK=spack to warm the from-source variant's sources too.
set -uo pipefail

_here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=scripts/common.sh
. "$_here/common.sh"

# Single concurrency knob. Small by default: this runs on a login node whose
# `ulimit -u` is low (~950 on Isambard 3), and submodule clones fork freely.
FETCH_JOBS="${FETCH_JOBS:-4}"

info() { echo "INFO: $*"; }
warn() { echo "WARN: $*" >&2; }
die()  { echo "ERROR: $*" >&2; exit 1; }

case "$LFRIC_STACK" in
  cray|spack) ;;
  *) die "LFRIC_STACK must be 'cray' or 'spack' (got '$LFRIC_STACK')" ;;
esac

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

# --- 1. Stage-1 submodules present (clone only if missing) -----------------
# Mirrors build.sh's presence check, but clones what is absent instead of failing
# — making this script self-sufficient login-node prep. Only the Stage-1 (core)
# submodules; the Stage-2 physics repos have their own task (pixi run init-physics).
CORE_SUBS=(spack spack-packages lfric_apps lfric_core mo-spack-packages)
_missing=()
for sub in "${CORE_SUBS[@]}"; do
  git -C "$REPO_ROOT/vendor/$sub" rev-parse --git-dir >/dev/null 2>&1 \
    || _missing+=("vendor/$sub")
done
if [ "${#_missing[@]}" -gt 0 ]; then
  info "Cloning missing Stage-1 submodules (--jobs $FETCH_JOBS): ${_missing[*]}"
  git -C "$REPO_ROOT" submodule update --init --recursive --jobs "$FETCH_JOBS" \
      -- "${_missing[@]}" \
    || die "submodule init failed for: ${_missing[*]} (private repos need Met Office SSO on your SSH key)"
else
  info "Stage-1 submodules already present — skipping clone"
fi

# --- 2. Concretize the selected variant ------------------------------------
# Delegated to build.sh so the env instantiation, config (incl. source_cache),
# module loads and the cray/spack solve assertions are defined in ONE place.
# STOP_AFTER_CONCRETIZE=1 stops it before the install; LFRIC_STACK is inherited.
info "Concretizing $ENV_NAME (via build.sh STOP_AFTER_CONCRETIZE=1)"
STOP_AFTER_CONCRETIZE=1 bash "$_here/build.sh" \
  || die "concretize step failed (see build.sh output above)"
[ -f "$SPACK_ENV_DIR/spack.lock" ] \
  || die "no concretized lock at $SPACK_ENV_DIR/spack.lock after concretize"

# --- 3. Fetch all sources into the persistent cache ------------------------
# With the env concretized, `spack -e <env> fetch` (no spec) downloads/clones the
# source of every spec in the DAG into $PREFIX/source-cache. Externals (cray-mpich,
# Cray HDF5/netCDF) have no source and are skipped. Sequential across packages, so
# no -j; nested git concurrency is already capped above.
[ -f "$SPACK_ROOT/share/spack/setup-env.sh" ] || die "vendored spack missing setup-env.sh"
# shellcheck source=/dev/null
. "$SPACK_ROOT/share/spack/setup-env.sh"
info "Fetching all sources for $ENV_NAME into $PREFIX/source-cache"
spack -e "$SPACK_ENV_DIR" fetch || die "spack fetch failed"

info "Sources cached under $PREFIX/source-cache — the compute-node build can run offline."
echo "FETCH_OK"
