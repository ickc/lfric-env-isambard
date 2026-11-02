#!/usr/bin/env bash
# container/fetch.sh — download every Spack source the image build needs into
# its persistent source cache, on the LOGIN node, before `sbatch build.sbatch`.
# The container's counterpart of Stage 1's `pixi run fetch`: optional, but it
# takes every source-host failure (gitlab.dkrz.de refusing robots, a flaky XIOS
# server) out of a multi-hour compute job and into a minute here.
#
# What it fetches:
#   1. Stage 1's spack variant WITH the container overlay (container/spack/env/),
#      solved by Stage 1's own fetch (stage1/fetch.sh) in a throwaway prefix —
#      sources depend on package versions, not on the OS or target, so the
#      host's solve fetches what the image's will need;
#   2. gcc@14.3.0 and its build dependencies, as the image's gcc stage builds it.
#
# What stays online in the build, deliberately: the Debian base image, apt, the
# pixi binary and its Python, and Spack's clingo bootstrap — the container's
# equivalent of Stage 1's pixi bootstrap, each one fetch from a large mirror.
#
# Same variables as build.sh (LFRIC_CONTAINER_BASE; PROJECTDIR, LOCALDIR).
# Ends with CONTAINER_FETCH_OK.
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." || exit 1
repo="$PWD"
die() { echo "ERROR: container/fetch.sh: $*" >&2; exit 1; }

[ -n "${PROJECTDIR:-}" ] || die "PROJECTDIR unset"
command -v pixi >/dev/null 2>&1 || die "pixi not on PATH (Stage 1 runs through it)"
base="${LFRIC_CONTAINER_BASE:-$PROJECTDIR/lfric-env/container}"
sources="$base/cache/source-cache"
# A private Stage 1 prefix: Stage 1's fetch instantiates and solves an env, and
# must never do that in a released one (it would rewrite its view).
fetch_base="$base/fetch"
version="$(tr -d '[:space:]' < stage1/VERSION)"
mkdir -p "$sources"
echo "sources: $sources"

# --- 1. the environment, through Stage 1's fetch --------------------------
cfg="$fetch_base/$version/spack-config/spack"
mkdir -p "$cfg"
# The overlay's solve-affecting files; not mirrors.yaml (its binary cache path
# exists only inside the build).
cp container/spack/env/packages.yaml container/spack/env/concretizer.yaml "$cfg"/
( cd stage1 && LFRIC_BASE="$fetch_base" LFRIC_SOURCE_CACHE="$sources" \
    LFRIC_MISC_CACHE="$fetch_base/misc-cache" FORCE_CONCRETIZE=1 pixi run fetch-spack ) \
  || die "Stage 1's fetch failed"

# --- 2. gcc@14.3.0, as the gcc stage builds it ----------------------------
# The gcc stage's config (vendored repo, deprecated versions allowed), with the
# source cache pointed here; the bootstrap compiler is whatever the host has —
# it does not change which sources gcc's build needs.
gcc_spec="$(sed -n 's/.*spack install -j "\$SPACK_JOBS" --fail-fast "\([^"]*\)".*/\1/p' container/Containerfile)"
[ -n "$gcc_spec" ] || die "could not read the gcc spec from container/Containerfile"
gcc_spec="${gcc_spec% %*}"   # drop the %bootstrap-compiler: the host has another
echo "gcc: $gcc_spec"
sed "s#/opt/lfric-env/src/stage1#$repo/stage1#" container/spack/gcc/repos.yaml > "$fetch_base/gcc-repos.yaml"
( cd stage1 && pixi run --frozen -- bash -c '
    export SPACK_USER_CONFIG_PATH="$1/gcc-config" SPACK_USER_CACHE_PATH="$1/gcc-cache"
    mkdir -p "$SPACK_USER_CONFIG_PATH"
    cp "$2/container/spack/gcc/packages.yaml" "$2/container/spack/gcc/concretizer.yaml" "$SPACK_USER_CONFIG_PATH"/
    cp "$1/gcc-repos.yaml" "$SPACK_USER_CONFIG_PATH/repos.yaml"
    . "$2/stage1/vendor/spack/share/spack/setup-env.sh"
    spack -c "config:source_cache:$3" -c config:deprecated:true fetch --dependencies "$4"
  ' _ "$fetch_base" "$repo" "$sources" "$gcc_spec" ) \
  || die "fetching gcc's sources failed"

echo "CONTAINER_FETCH_OK — $(du -sh "$sources" | cut -f1) in $sources"
