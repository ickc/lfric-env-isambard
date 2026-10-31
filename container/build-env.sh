#!/usr/bin/env bash
# container/build-env.sh — the Containerfile's build stage: run Stage 1's spack
# variant build in the image, then freeze its module (gen-env.sh). Runs in
# /opt/lfric-env/src/stage1, with stage1/env.sh's site variables set by the
# Containerfile's ENV and SPACK_JOBS passed in.
#
# A script rather than RUN lines because it needs bash: Lmod's `module` is a
# shell function, and Stage 1's smoke test (lfric_smoke_test, in build.sh, a
# child bash) finds it only if it is exported, as it is in a host login shell.
set -euo pipefail
. /usr/share/lmod/lmod/init/bash
export -f module ml

# The container's Spack overlay (container/spack/env/) goes in the user config
# scope stage1/env.sh names for the spack variant. lib.sh only ever writes
# config.yaml there, so these files survive the build.
cfg="$(LFRIC_STACK=spack pixi run --frozen -- bash -c 'echo "$SPACK_USER_CONFIG_PATH"')"
[ -n "$cfg" ] || { echo "ERROR: build-env.sh: no SPACK_USER_CONFIG_PATH from stage1/env.sh" >&2; exit 1; }
mkdir -p "$cfg"
cp /opt/lfric-env/build/spack-overlay/*.yaml "$cfg"/
echo "INFO: container overlay in $cfg: $(cd "$cfg" && echo *.yaml)"

# Stage 1, exactly as `pixi run build-spack` runs it on the host. A failed
# build's stage dies with the build container, and Spack prints only the tail
# of its log; so first copy every failed package's full log onto the cache
# mount, which outlives the build (container/build.sh: $LFRIC_CONTAINER_BASE/cache).
if ! pixi run --frozen build-spack; then
  logs="/var/cache/lfric/failed-logs/$(date -u +%Y%m%dT%H%M%SZ)"
  mkdir -p "$logs"
  for d in "$LOCALDIR"/lfric-build-spack/*/spack-stage-*/; do
    [ -f "$d/spack-build-out.txt" ] || continue
    n="$(basename "$d")"
    cp "$d/spack-build-out.txt" "$logs/$n.out.txt"
    [ -f "$d/spack-build-env.txt" ] && cp "$d/spack-build-env.txt" "$logs/$n.env.txt"
  done
  echo "ERROR: build-env.sh: Stage 1's build failed; full logs in \$LFRIC_CONTAINER_BASE/cache/failed-logs/$(basename "$logs")" >&2
  exit 1
fi
rm -rf "$LOCALDIR"

# The frozen module environment and the MPI swap links (gen-env.sh).
LFRIC_STACK=spack pixi run --frozen bash /opt/lfric-env/build/gen-env.sh
