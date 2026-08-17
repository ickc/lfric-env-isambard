#!/usr/bin/env bash
# fetch.sh — download every source the build needs, on the LOGIN node.
# `pixi run fetch` (or fetch-spack).
#
# Optional, but do it. Compute nodes here do have outbound network, so the build
# works without this — but then hours of allocated node time depend on a set of
# third-party hosts staying up, and one of them (gitlab.in2p3.fr, which serves
# the XIOS clone) fails intermittently. Fetching first moves that risk onto a
# login node where a retry is free.
#
# It shares lfric_prepare + lfric_concretize with build.sh, so the sources it
# caches are provably the ones the build will ask for. The cache lives at
# $LFRIC_SOURCE_CACHE (under LFRIC_BASE, shared across env versions) and is
# content-addressed, so this stays useful across version bumps.
set -uo pipefail
# Re-source the configuration in this process, so an inline override such as
# `LFRIC_STACK=spack bash build.sh` re-derives every path that depends on it.
cd -- "$(dirname -- "${BASH_SOURCE[0]}")" || exit 1
. ./env.sh || exit 1
. ./lib.sh

# Login nodes cap processes at ~900 and git submodule clones fan out freely.
# Inject the cap via GIT_CONFIG_* so it reaches every git we spawn, including
# the ones Spack runs itself — a --jobs flag would only apply to our own.
FETCH_JOBS="${FETCH_JOBS:-4}"
_n="${GIT_CONFIG_COUNT:-0}"
export "GIT_CONFIG_KEY_${_n}=submodule.fetchJobs"
export "GIT_CONFIG_VALUE_${_n}=$FETCH_JOBS"
export GIT_CONFIG_COUNT="$((_n + 1))"

lfric_prepare
lfric_concretize
lfric_fetch

echo "FETCH_OK"
