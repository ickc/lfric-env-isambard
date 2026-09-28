#!/usr/bin/env bash
# scripts/common.sh — shared context for the examples (Stage 2). SOURCE it.
#
# Its whole job is to work out WHICH built environment to load and where its
# modulefiles are, so an example can `module load` it. It does not know how that
# environment was built — that is stage1/, which shares nothing with this file
# but the two values below.
#
# NOTE (2026-08-17): Stage 1 has moved to stage1/ and is now self-contained;
# this file is what is left of the old shared common.sh, trimmed to what the
# examples actually read. It still hardcodes the layout stage1/env.sh chooses
# (LFRIC_BASE, the modulefile naming), which is a duplication to remove when the
# examples are ported — the right long-term answer is for them to take
# $MODULEFILES_DIR and the module name as input rather than re-derive them.

REPO_ROOT="${PIXI_PROJECT_ROOT:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")/.." && pwd)}"
export REPO_ROOT

# Which environment to load. These two must match what Stage 1 built:
#   ./VERSION       keep in step with stage1/VERSION
#   LFRIC_STACK     cray (the only variant with working multi-node MPI here)
if [ -z "${LFRIC_ENV_VERSION:-}" ] && [ -r "$REPO_ROOT/VERSION" ]; then
  LFRIC_ENV_VERSION="$(tr -d '[:space:]' < "$REPO_ROOT/VERSION")"
fi
export LFRIC_ENV_VERSION="${LFRIC_ENV_VERSION:-unversioned}"
export LFRIC_STACK="${LFRIC_STACK:-cray}"

# Where Stage 1 installed it (stage1/env.sh derives the same paths).
export BASE="${LFRIC_PREFIX:-${PROJECTDIR:-${SCRATCH:-$HOME}}/$USER/opt/$(uname -sm | tr ' ' -)}"
export PREFIX="$BASE/$LFRIC_ENV_VERSION"
export ENV_NAME="lfric-apps-isambard-$LFRIC_STACK"

# The contract: one `module use`, then `module load $MODULE_NAME`. MODULEFILE
# doubles as the "is this variant built?" sentinel.
export MODULEFILES_DIR="$BASE/modulefiles"
export MODULE_NAME="lfric-env/$LFRIC_ENV_VERSION/$LFRIC_STACK"
export MODULEFILE="$MODULEFILES_DIR/lfric-env/$LFRIC_ENV_VERSION/$LFRIC_STACK.lua"

case ":${MODULEPATH:-}:" in
  *":$MODULEFILES_DIR:"*) : ;;
  *) export MODULEPATH="$MODULEFILES_DIR${MODULEPATH:+:$MODULEPATH}" ;;
esac
