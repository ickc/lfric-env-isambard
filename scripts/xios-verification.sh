#!/usr/bin/env bash

set -euo pipefail

XIOS_GIT_URL="${XIOS_GIT_URL:-https://gitlab.in2p3.fr/ipsl/projets/xios-projects/xios.git}"
XIOS_GIT_BRANCH="${XIOS_GIT_BRANCH:-XIOS2}"
XIOS_GIT_COMMIT="${XIOS_GIT_COMMIT:-26cc7d88e4f3fa1960461b377d9b8c82550a180e}"
XIOS_SVN_REVISION="${XIOS_SVN_REVISION:-2252}"
KEEP_XIOS_VERIFICATION_CLONE="${KEEP_XIOS_VERIFICATION_CLONE:-0}"
XIOS_WORKDIR="${XIOS_WORKDIR:-}"

info() {
  echo "INFO: $*"
}

warn() {
  echo "WARN: $*" >&2
}

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

require_command() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    fail "Required command '$cmd' was not found in PATH."
  fi
}

require_command git
require_command mktemp
require_command grep

if [ -n "$XIOS_WORKDIR" ]; then
  mkdir -p "$XIOS_WORKDIR"
  workdir="$XIOS_WORKDIR"
else
  workdir="$(mktemp -d "${TMPDIR:-/tmp}/xios-verification.XXXXXX")"
fi

cleanup() {
  if [ "${KEEP_XIOS_VERIFICATION_CLONE}" = "1" ]; then
    info "Keeping XIOS verification checkout at $workdir"
    return 0
  fi
  rm -rf "$workdir"
}
trap cleanup EXIT

repo_dir="$workdir/xios"
rm -rf "$repo_dir"

info "Verifying XIOS source availability from $XIOS_GIT_URL"
info "Expecting branch $XIOS_GIT_BRANCH, commit $XIOS_GIT_COMMIT, former SVN revision $XIOS_SVN_REVISION"

if ! git ls-remote --exit-code "$XIOS_GIT_URL" "refs/heads/$XIOS_GIT_BRANCH" >/dev/null 2>&1; then
  fail "XIOS branch '$XIOS_GIT_BRANCH' is not reachable at $XIOS_GIT_URL."
fi

if ! git clone --filter=blob:none --no-checkout --branch "$XIOS_GIT_BRANCH" --single-branch \
    "$XIOS_GIT_URL" "$repo_dir" >/dev/null 2>&1; then
  warn "Partial clone failed; retrying with a full single-branch clone."
  git clone --no-checkout --branch "$XIOS_GIT_BRANCH" --single-branch \
    "$XIOS_GIT_URL" "$repo_dir" >/dev/null 2>&1 || \
    fail "Unable to clone XIOS branch '$XIOS_GIT_BRANCH' from $XIOS_GIT_URL."
fi

if ! git -C "$repo_dir" rev-parse --verify "${XIOS_GIT_COMMIT}^{commit}" >/dev/null 2>&1; then
  fail "Commit $XIOS_GIT_COMMIT is not present in branch '$XIOS_GIT_BRANCH'."
fi

if ! git -C "$repo_dir" merge-base --is-ancestor "$XIOS_GIT_COMMIT" "origin/$XIOS_GIT_BRANCH"; then
  fail "Commit $XIOS_GIT_COMMIT is not an ancestor of origin/$XIOS_GIT_BRANCH."
fi

commit_body="$(git -C "$repo_dir" show -s --format=%B "$XIOS_GIT_COMMIT")"
if ! printf '%s\n' "$commit_body" | grep -Eq "git-svn-id:[[:space:]].*@${XIOS_SVN_REVISION}[[:space:]]"; then
  fail "Commit $XIOS_GIT_COMMIT does not advertise former SVN revision $XIOS_SVN_REVISION."
fi

git -C "$repo_dir" checkout --quiet "$XIOS_GIT_COMMIT"

required_paths=(
  make_xios
  arch
  src
  extern
)

for path in "${required_paths[@]}"; do
  if [ ! -e "$repo_dir/$path" ]; then
    fail "Required XIOS path '$path' is missing at commit $XIOS_GIT_COMMIT."
  fi
done

info "Verified XIOS commit: $(git -C "$repo_dir" show -s --format='%H %s' "$XIOS_GIT_COMMIT")"
info "Verified XIOS branch head: $(git -C "$repo_dir" rev-parse "origin/$XIOS_GIT_BRANCH")"
info "XIOS source checkout is usable for the Spack build."
