#!/usr/bin/env bash
# print-pins.sh — print the vendored-submodule pin table (Markdown) for the
# README "Pinned versions" section.
#
# This is the single source of truth for "what commit is each submodule, what
# release/branch does it correspond to, and how is it pinned" — so the README
# table is GENERATED rather than hand-maintained, and uses ONE describe
# convention. (Hand-written labels drift: `git describe` with vs without --tags
# can name a different nearest tag, e.g. jules' 2026.03.2 annotated tag vs a
# closer 2026.03.1 lightweight tag.) We use plain `git describe` (annotated tags
# only), matching what `git submodule status` shows, and fall back to a branch
# label for repos with no annotated tag (e.g. mo-spack-packages tracks `main`).
#
# Usage (from a checkout with the submodules present):
#   bash scripts/print-pins.sh        # or: pixi run print-pins
# then paste the output into README.md under "Pinned versions".
set -uo pipefail

_here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd -- "$_here/.." && pwd)"
cd "$REPO_ROOT" || exit 1

printf '| Submodule | Commit | Nearest ref | Pinned at |\n'
printf '|-----------|--------|-------------|-----------|\n'

# Submodule paths, in .gitmodules order.
git config --file .gitmodules --get-regexp '^submodule\..*\.path$' \
  | awk '{print $2}' \
  | while read -r path; do
  if ! git -C "$path" rev-parse --git-dir >/dev/null 2>&1; then
    printf '| `%s` | _(not checked out — run `submodule-init`)_ |  |  |\n' "$path"
    continue
  fi
  sha="$(git -C "$path" rev-parse --short=8 HEAD 2>/dev/null)"
  if tag="$(git -C "$path" describe --exact-match HEAD 2>/dev/null)"; then
    ref="\`$tag\`"; how="exact tag"
  elif desc="$(git -C "$path" describe 2>/dev/null)"; then
    # desc is <tag>-<N>-g<sha>; strip the trailing -<N>-g<sha> to get the tag.
    tag="${desc%-*-g*}"; n="${desc#"$tag"-}"; n="${n%-g*}"
    ref="\`$tag\`"; how="$n commits past tag"
  else
    # No annotated tag reachable: label it by branch/ref instead.
    allref="$(git -C "$path" describe --all --always 2>/dev/null)"
    allref="${allref#heads/}"; allref="${allref#remotes/origin/}"; allref="${allref#tags/}"
    ref="\`$allref\`"; how="branch tip (untagged)"
  fi
  printf '| `%s` | `%s` | %s | %s |\n' "$path" "$sha" "$ref" "$how"
done
