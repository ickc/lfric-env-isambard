#!/usr/bin/env bash
# examples/science-suites/site/extract-sources.sh — science-suite per-suite OFFLINE
# LFRic source extraction (the "dependencies.yaml" mechanism).
#
# Reads a suite's dependencies.yaml and materialises each declared repo@ref from
# THIS repo's VENDORED LOCAL MIRRORS (vendor/lfric_apps, vendor/lfric_core,
# vendor/physics/{casim,jules,socrates,ukca}) into SOURCE_ROOT — with NO network.
# It then applies the repo's LFRic-source patch stack to the extracted tree.
#
# Why this exists: the vendored submodules are FULL local clones, not single
# pinned checkouts — they carry every fetched branch/tag. So a suite can declare
# *which ref* of each repo to build (its science), and we extract that ref offline
# via `git archive`. This is the per-experiment source axis the upstream suites
# express via dependencies.yaml, made reproducible/offline for this repo.
#
# OFFLINE CONTRACT: a ref is extractable iff it is already present in the local
# mirror. This script NEVER fetches. A missing ref (or a fork on another remote)
# must be staged once, online, into the mirror first — e.g.
#   git -C vendor/lfric_apps remote add <fork> <url> && git -C vendor/lfric_apps fetch <fork>
# then re-run. In strict-offline mode (default) a missing ref is a hard error
# naming exactly what to stage. See examples/science-suites/README.md.
#
# Usage:  extract-sources.sh <dependencies.yaml> <SOURCE_ROOT> [REPO_ROOT]
set -euo pipefail

DEPS="${1:?usage: extract-sources.sh <dependencies.yaml> <SOURCE_ROOT> [REPO_ROOT]}"
SOURCE_ROOT="${2:?usage: extract-sources.sh <dependencies.yaml> <SOURCE_ROOT> [REPO_ROOT]}"
REPO_ROOT="${3:-${REPO_ROOT:-}}"

die()  { echo "ERROR: $*" >&2; exit 1; }
info() { echo "INFO: extract-sources: $*"; }

[ -f "$DEPS" ]      || die "dependencies.yaml not found: $DEPS"
[ -n "$REPO_ROOT" ] || die "REPO_ROOT not set (pass as \$3 or env)"
[ -d "$REPO_ROOT/vendor" ] || die "no vendor/ mirrors under REPO_ROOT=$REPO_ROOT"
command -v python3 >/dev/null 2>&1 || die "python3 required to parse dependencies.yaml"

# vendor/ mirror path for a repo name; empty => not an LFRic-source repo we mirror.
mirror_for() {
  case "$1" in
    lfric_apps|lfric_core)       echo "$REPO_ROOT/vendor/$1" ;;
    casim|jules|socrates|ukca)   echo "$REPO_ROOT/vendor/physics/$1" ;;
    *)                           echo "" ;;
  esac
}
# Where each repo is extracted to (the layout flow.cylc's *_ROOT_DIR expect).
dest_for() {
  case "$1" in
    lfric_apps)                  echo "$SOURCE_ROOT/lfric_apps" ;;
    lfric_core)                  echo "$SOURCE_ROOT/lfric_core" ;;
    casim|jules|socrates|ukca)   echo "$SOURCE_ROOT/physics/$1" ;;
  esac
}

# Parse dependencies.yaml -> lines of "<name>\t<ref>\t<source>". Uses PyYAML if
# present (it ships in the env view), else a minimal parser for the scalar form.
# A repo may declare a single {source,ref} or a list; we take the FIRST entry
# (the base ref) — merging fork branches is not yet supported offline (see README).
parse_deps() {
  python3 - "$DEPS" <<'PYEOF'
import sys
path = sys.argv[1]
try:
    import yaml
    with open(path) as fh:
        data = yaml.safe_load(fh) or {}
except Exception:
    # Minimal fallback: top-level "name:" blocks with indented "ref:"/"source:".
    data, cur = {}, None
    for raw in open(path):
        line = raw.rstrip("\n")
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        if not line[:1].isspace() and line.rstrip().endswith(":"):
            cur = line.strip()[:-1]; data[cur] = {}
        elif cur is not None and ":" in line:
            k, _, v = line.strip().partition(":")
            k = k.lstrip("- ").strip()
            v = v.strip()
            # Drop an inline YAML comment (whitespace + '#') before using the value:
            # the dependencies.yaml refs are written `ref: <sha>   # <describe>`, and
            # without this the value would be "<sha>   # ..." and git rev-parse fails.
            for _sep in (" #", "\t#"):
                _i = v.find(_sep)
                if _i != -1:
                    v = v[:_i].rstrip()
            data[cur].setdefault(k.strip(), v.strip("'\""))
for name, spec in (data or {}).items():
    if isinstance(spec, list):
        spec = spec[0] if spec else {}
    ref = (spec or {}).get("ref", "") or ""
    src = (spec or {}).get("source", "") or ""
    print(f"{name}\t{ref}\t{src}")
PYEOF
}

info "dependencies: $DEPS"
info "SOURCE_ROOT:  $SOURCE_ROOT"
mkdir -p "$SOURCE_ROOT"

n=0
while IFS=$'\t' read -r name ref source; do
  [ -n "$name" ] || continue
  mirror="$(mirror_for "$name")"
  if [ -z "$mirror" ]; then
    info "skip '$name' (not an LFRic-source repo this repo mirrors)"; continue
  fi
  git -C "$mirror" rev-parse --git-dir >/dev/null 2>&1 \
    || die "mirror for '$name' not initialised: $mirror (run: pixi run submodule-init)"
  [ -n "$ref" ] || die "no ref declared for '$name' in $DEPS"

  # Resolve the declared ref to a commit IN THE LOCAL MIRROR. No fetch.
  commit="$(git -C "$mirror" rev-parse --verify --quiet "${ref}^{commit}" || true)"
  if [ -z "$commit" ]; then
    die "ref '$ref' for '$name' is NOT in the local mirror ($mirror).
       Offline extraction needs it staged first, e.g.:
         git -C $mirror fetch --tags origin            # if it's a new mainline ref
         git -C $mirror remote add <fork> <url> && git -C $mirror fetch <fork>  # if a fork
       then re-run. (This script never fetches — it honours the offline invariant.)"
  fi

  dest="$(dest_for "$name")"
  info "extract $name @ $ref ($(git -C "$mirror" describe --tags --always "$commit" 2>/dev/null || echo "$commit")) -> $dest"
  rm -rf "$dest"; mkdir -p "$dest"
  git -C "$mirror" archive "$commit" | tar -x -C "$dest"
  n=$((n+1))
done < <(parse_deps)

[ "$n" -gt 0 ] || die "no source repos extracted from $DEPS"
info "extracted $n source repo(s)"

# Apply the LFRic-source patch stack to the EXTRACTED tree (not vendor/). The
# patches are idempotent and skip cleanly when a target file is absent, so they
# tolerate ref-to-ref drift. Only lfric_apps/lfric_core patches apply here; the
# spack-packages patches are env tooling (Stage 1), not suite source.
shopt -s nullglob
for p in "$REPO_ROOT"/patches/*-lfric_core-*-patch.sh "$REPO_ROOT"/patches/*-lfric_apps-*-patch.sh; do
  info "patch $(basename "$p")"
  LFRIC_SRC_ROOT="$SOURCE_ROOT" bash "$p" || die "patch failed on extracted tree: $p"
done
info "patch stack applied to $SOURCE_ROOT"
echo "EXTRACT_SOURCES_OK"
