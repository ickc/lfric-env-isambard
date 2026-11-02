#!/usr/bin/env bash
# container/build.sh — build the LFRic environment image, convert it to a SIF,
# and (PUSH=1) push it to the registry. Run it on a COMPUTE node, through
# container/build.sbatch: inside, it is Stage 1's full build.
#
# Every input is an environment variable, defaulted below and printed at the
# start; nothing is inferred. The image itself is built by podman (podman-hpc
# on Isambard 3), from container/Containerfile with the repo root as context.
#
#   LFRIC_CONTAINER_BASE   persistent area: the Spack caches and the SIFs.
#                          Default $PROJECTDIR/lfric-env/container.
#   LFRIC_CONTAINER_REPO   image name.        Default ghcr.io/ickc/lfric-env
#   LFRIC_CONTAINER_TAG    image tag.         Default stage1/VERSION
#   SPACK_JOBS             build parallelism. Default 16
#   PODMAN                 the podman CLI.    Default podman-hpc
#   PUSH                   1 = push the image (and the SIF, as an OCI artifact
#                          tagged <tag>-sif) after building. Default 0.
#   SEED_SOURCE_CACHE      optional: a Stage 1 source cache (a host build's
#                          $LFRIC_BASE/source-cache) to copy into the build's own
#                          before building. Read only; the same package set, so
#                          a source host that is down or refusing robots (as
#                          gitlab.dkrz.de does for yaxt) does not stop the build.
#
# The Spack caches under $LFRIC_CONTAINER_BASE/cache are bind-mounted into the
# build: sources and a binary cache every package is pushed to as it installs,
# so a failed or repeated build restarts from what is already built. They are
# NOT in the image.
#
# Ends with CONTAINER_BUILD_OK and the SIF's path.
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." || exit 1
die() { echo "ERROR: container/build.sh: $*" >&2; exit 1; }

[ -n "${PROJECTDIR:-}" ] || die "PROJECTDIR unset (set LFRIC_CONTAINER_BASE, or PROJECTDIR)"
[ -n "${LOCALDIR:-}" ]   || die "LOCALDIR unset: podman needs node-local disk for its storage and temp files"
version="$(tr -d '[:space:]' < stage1/VERSION)"
base="${LFRIC_CONTAINER_BASE:-$PROJECTDIR/lfric-env/container}"
repo="${LFRIC_CONTAINER_REPO:-ghcr.io/ickc/lfric-env}"
tag="${LFRIC_CONTAINER_TAG:-$version}"
jobs="${SPACK_JOBS:-16}"
podman="${PODMAN:-podman-hpc}"
push="${PUSH:-0}"
cache="$base/cache"
sif="$base/lfric-env_$tag.sif"
# Podman writes multi-GB layers through its temp dir, which defaults to /var/tmp.
work="$LOCALDIR/lfric-container-build"
export TMPDIR="$work/tmp" APPTAINER_TMPDIR="$work/apptainer-tmp" APPTAINER_CACHEDIR="$work/apptainer-cache"

echo "image:   $repo:$tag   (LFRIC_ENV_VERSION=$version)"
echo "base:    $base"
echo "cache:   $cache"
echo "jobs:    $jobs    podman: $podman    push: $push"
[ "$(cat VERSION)" = "$version" ] || die "VERSION ($(cat VERSION)) and stage1/VERSION ($version) disagree"
for s in spack spack-packages mo-spack-packages; do
  [ -e "stage1/vendor/$s/.git" ] || die "stage1/vendor/$s is not initialized (cd stage1 && pixi run submodules)"
done
mkdir -p "$cache" "$TMPDIR" "$APPTAINER_TMPDIR" "$APPTAINER_CACHEDIR"

# Rootless podman unpacks images as many uids (Debian's base alone uses 0..42),
# mapped through /etc/subuid. Node-local podman state left by an earlier run can
# hold a stale single-uid mapping ("insufficient UIDs or GIDs available in user
# namespace"); `system migrate` refreshes it. Then check, so a node without a
# subuid range fails here in seconds rather than at the first layer.
"$podman" system migrate >/dev/null 2>&1 || true
uids="$("$podman" unshare cat /proc/self/uid_map | awk '{ n += $3 } END { print n + 0 }')"
[ "$uids" -gt 65535 ] \
  || die "rootless podman on $(hostname) maps only $uids uid(s); check /etc/subuid for $(id -un)"

if [ -n "${SEED_SOURCE_CACHE:-}" ]; then
  [ -d "$SEED_SOURCE_CACHE" ] || die "SEED_SOURCE_CACHE=$SEED_SOURCE_CACHE: no such directory"
  echo "seeding: $SEED_SOURCE_CACHE -> $cache/source-cache"
  mkdir -p "$cache/source-cache"
  cp -rn "$SEED_SOURCE_CACHE/." "$cache/source-cache/" || die "could not seed the source cache"
fi

# /tmp in every build step is a node-local directory, not the container's own
# filesystem. Rootless podman (podman-hpc) gives a build container a
# fuse-overlayfs root, and heavily parallel builds on it came out silently
# broken: XIOS failed to link on CAttributeMap symbols its archive should have
# held, and matplotlib's _path.so lost agg symbols — both building under /tmp,
# both fine on a real filesystem. Every Spack build stage and pip temp dir is
# under /tmp (the Containerfile puts LOCALDIR there), so none of it touches the
# overlay; only finished installs are copied into the image.
build_tmp="$work/build-tmp"
rm -rf "$build_tmp"; mkdir -p "$build_tmp"; chmod 1777 "$build_tmp"

"$podman" build \
  --file container/Containerfile \
  --build-arg "SPACK_JOBS=$jobs" \
  --build-arg "LFRIC_ENV_VERSION=$version" \
  --volume "$cache:/var/cache/lfric" \
  --volume "$build_tmp:/tmp" \
  --tag "$repo:$tag" \
  . || die "podman build failed"

# The SIF, for Apptainer. Converted from the image just built, so the two are
# the same filesystem; `apptainer pull docker://$repo:$tag` would give the same.
archive="$work/lfric-env_$tag.oci.tar"
rm -f "$archive"
"$podman" save --format oci-archive --output "$archive" "$repo:$tag" || die "podman save failed"
apptainer build --force "$sif.partial" "oci-archive://$archive" || die "apptainer build failed"
mv -f "$sif.partial" "$sif"
rm -f "$archive"
ls -l "$sif"

if [ "$push" = 1 ]; then
  registry="${repo%%/*}"
  owner="${repo#*/}"; owner="${owner%%/*}"
  # The token is gh's, with the write:packages scope (gh auth refresh -s
  # write:packages). It is handed to each push for that push only — a throwaway
  # auth file for podman, environment variables for apptainer — and never
  # stored: `podman login`/`apptainer registry login` would write it, in plain
  # text, to the user's home.
  token="$(gh auth token)" || die "no gh token (gh auth login)"
  authfile="$work/auth.json"
  trap 'rm -f "$authfile"' EXIT
  printf '%s' "$token" | "$podman" login --authfile "$authfile" "$registry" --username "$owner" --password-stdin \
    || die "could not log in to $registry as $owner"
  "$podman" push --authfile "$authfile" "$repo:$tag" || die "push of $repo:$tag failed"
  rm -f "$authfile"
  APPTAINER_DOCKER_USERNAME="$owner" APPTAINER_DOCKER_PASSWORD="$token" \
    apptainer push "$sif" "oras://$repo:$tag-sif" || die "push of the SIF failed"
  echo "pushed: docker://$repo:$tag  oras://$repo:$tag-sif"
fi

echo "CONTAINER_BUILD_OK — $sif"
