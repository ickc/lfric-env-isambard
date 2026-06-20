#!/usr/bin/env bash
# Target submodule: vendor/lfric_apps
#
# Make external-source staging reproducible and offline. Upstream local_build.py
# (via build/extract/get_git_sources.py) automagically clones/rsyncs/git-fetches
# the science sources (lfric_core, and casim/jules/socrates/ukca when PHYSICS_ROOT
# is unset) during the build — which (a) can silently change the stack and (b)
# emits a confusing "fatal: not a git repository" warning when handed a submodule.
#
# This patch rewrites get_source() so it NEVER clones, copies, fetches or mutates
# anything: external sources are pinned git submodules the user stages explicitly
# (`pixi run submodule-init`; update with `pixi run stage-physics`). get_source
# symlinks the staged tree into the location the build expects and sanity-checks
# it; a remote (.git) source now raises instead of silently fetching.
set -o pipefail
_here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="${PIXI_PROJECT_ROOT:-$(cd "$_here/.." && pwd)}"
WORKING_DIR="$REPO_ROOT/vendor"
info() { echo "INFO: $*"; }
warn() { echo "WARN: $*" >&2; }
fail() { echo "ERROR: $*" >&2; return 1; }

patch_local_sources() {
  local f="$WORKING_DIR/lfric_apps/build/extract/get_git_sources.py"
  if [ ! -f "$f" ]; then
    warn "get_git_sources.py not found at $f; skipping local-sources patch."
    return 0
  fi
  if grep -q "PATCHED (lfric-env-isambard)" "$f"; then
    return 0
  fi
  command -v python3 >/dev/null 2>&1 || { warn "python3 unavailable; cannot apply local-sources patch."; return 0; }

  local repl
  repl="$(cat <<'PYEOF'
def get_source(
    source: str,
    ref: str,
    dest: Path,
    repo: str,
    use_mirrors: bool = False,
    mirror_loc: Path = Path(""),
) -> None:
    """
    PATCHED (lfric-env-isambard): no network clone, no rsync, no git fetch.

    External sources are pinned git submodules the user stages explicitly
    (``pixi run submodule-init``; update via ``pixi run stage-physics``). This
    symlinks the staged tree into place and sanity-checks it -- it never clones,
    copies, fetches or mutates the source, so builds are reproducible & offline.
    """
    if ".git" in source:
        raise RuntimeError(
            f"[lfric-env] remote fetching is disabled for reproducibility; "
            f"stage '{repo}' as a pinned submodule (got source={source!r}). "
            f"Run: pixi run submodule-init"
        )
    src = Path(source).resolve()
    if not src.is_dir():
        raise RuntimeError(
            f"[lfric-env] staged source for '{repo}' missing at {src}. "
            f"Run: pixi run submodule-init"
        )
    if dest.is_symlink() or dest.exists():
        if dest.is_dir() and not dest.is_symlink():
            rmtree(dest)
        else:
            dest.unlink()
    dest.parent.mkdir(parents=True, exist_ok=True)
    dest.symlink_to(src)
    logger.info(f"[{datetime_str()}] lfric-env: staged {repo} in place: {dest} -> {src}")
PYEOF
)"

  REPL="$repl" python3 - "$f" <<'PYEOF' || { fail "failed to splice get_source() in $f"; return 1; }
import os, sys
p = sys.argv[1]
s = open(p).read()
i = s.find("def get_source(")
j = s.find("def merge_source(")
if i < 0 or j < 0 or j <= i:
    sys.stderr.write("get_source/merge_source anchors not found; aborting\n")
    sys.exit(1)
open(p, "w").write(s[:i] + os.environ["REPL"] + "\n\n\n" + s[j:])
PYEOF

  python3 -c "import ast; ast.parse(open('$f').read())" \
    || { fail "patched $f is not valid Python"; return 1; }
  info "Patched get_source() in lfric_apps for staged, offline source handling."
}

patch_local_sources
exit $?
