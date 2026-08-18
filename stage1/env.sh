#!/usr/bin/env bash
# stage1/env.sh — every environment variable the Stage-1 build uses, in one place.
#
# SOURCE this; do not run it. pixi sources it on every `pixi run` / `pixi shell`
# (see [activation] in pixi.toml), and running Stage 1 through pixi is the only
# supported route — so by the time any script here executes, everything below is
# already exported. Nothing in Stage 1 infers a path at runtime: if you want to
# know where something lands, read this file.
#
# Two sections: what the SITE must provide (checked, never guessed), and what
# this build DERIVES from it (all overridable by exporting the var beforehand).

# --- 1. What the site must provide -----------------------------------------
# Isambard 3 sets all three in the default login environment. They are checked
# rather than defaulted: a wrong guess here silently installs gigabytes in the
# wrong filesystem, and the right value is not inferable.
#
#   PROJECTDIR  shared project space (/projects/u35v) — the install lives here,
#               group-readable, so colleagues can `module load` it.
#   LOCALDIR    node-local NVMe (/local/user/<uid>) — the transient Spack build
#               stage. Metadata-heavy; on contended Lustre the install crawls.
#   USER        your username; namespaces the install under PROJECTDIR.
_lfric_missing=""
[ -n "${PROJECTDIR:-}" ] || _lfric_missing="$_lfric_missing PROJECTDIR"
[ -n "${LOCALDIR:-}" ]   || _lfric_missing="$_lfric_missing LOCALDIR"
[ -n "${USER:-}" ]       || _lfric_missing="$_lfric_missing USER"
if [ -n "$_lfric_missing" ]; then
  echo "ERROR: stage1/env.sh: unset site variable(s):$_lfric_missing" >&2
  echo "       On Isambard 3 these come from the default login environment." >&2
  echo "       Set them explicitly if you are porting this elsewhere, e.g.:" >&2
  echo "         export PROJECTDIR=/projects/<project>   # shared, persistent" >&2
  echo "         export LOCALDIR=/tmp                    # node-local, transient" >&2
  unset _lfric_missing
  return 1 2>/dev/null || exit 1
fi
unset _lfric_missing

# pixi supplies the Python that runs Spack (3.11; Spack 1.0 needs < 3.12) and
# exports PIXI_PROJECT_ROOT. Its absence means someone bypassed pixi.
if [ -z "${PIXI_PROJECT_ROOT:-}" ]; then
  echo "ERROR: stage1/env.sh: PIXI_PROJECT_ROOT unset — Stage 1 runs through pixi." >&2
  echo "       From the stage1/ directory:  pixi run build   (see stage1/README.md)" >&2
  return 1 2>/dev/null || exit 1
fi
export STAGE1_DIR="$PIXI_PROJECT_ROOT"

# --- 2. What this build derives --------------------------------------------
# Only the knobs below read an existing value (so you can override them):
# LFRIC_STACK, LFRIC_ENV_VERSION, LFRIC_BASE and the two caches. Every other
# variable is assigned unconditionally, and that is what makes this
# file safe to source twice — pixi sources it once at activation, and each
# driver sources it again, so `LFRIC_STACK=spack bash build.sh` re-derives every
# variant-dependent path instead of inheriting the ones activation computed.

# Which dependency stack satisfies MPI and parallel I/O.
#   cray  (default) system cray-mpich + Cray HDF5/netCDF externals. The only
#         variant with working multi-node MPI (Slingshot/cxi) — run everything here.
#   spack everything from source except the compiler. Portable fallback; kept so
#         the build stays honest. Single-node/TCP at best; not for real runs.
export LFRIC_STACK="${LFRIC_STACK:-cray}"
case "$LFRIC_STACK" in
  cray|spack) ;;
  *) echo "ERROR: LFRIC_STACK must be 'cray' or 'spack' (got '$LFRIC_STACK')" >&2
     return 1 2>/dev/null || exit 1 ;;
esac

# The environment's own version (CalVer), read verbatim from stage1/VERSION. It
# names the install dir and the module, so every build lands somewhere distinct
# and a rebuild never overwrites an environment someone is currently loading.
# Bump it by editing stage1/VERSION. (Distinct from any LFRic apps/core version.)
if [ -z "${LFRIC_ENV_VERSION:-}" ]; then
  LFRIC_ENV_VERSION="$(tr -d '[:space:]' < "$STAGE1_DIR/VERSION")"
fi
export LFRIC_ENV_VERSION

# Where everything lands.
#   LFRIC_BASE         per-architecture container, SHARED across env versions.
#                      Holds the modulefiles and the download caches, so a new
#                      version reuses already-downloaded sources.
#   LFRIC_PREFIX       this version's install: $LFRIC_BASE/$LFRIC_ENV_VERSION.
#                      Both variants share its opt/ (Spack's store is content-
#                      addressed — though in practice the two variants share
#                      only about a fifth of their specs; see README §2).
#   LFRIC_WORKING_DIR  transient Spack build stage, node-local. Disposable —
#                      point LOCALDIR elsewhere if a node has no local disk.
export LFRIC_BASE="${LFRIC_BASE:-$PROJECTDIR/$USER/opt/$(uname -sm | tr ' ' -)}"
export LFRIC_PREFIX="$LFRIC_BASE/$LFRIC_ENV_VERSION"
export LFRIC_WORKING_DIR="$LOCALDIR/lfric-build-$LFRIC_STACK"

# Spack. The CLI is the vendored submodule; its user config and caches are
# redirected under our own prefix so the build never reads or writes ~/.spack.
# The download caches sit at LFRIC_BASE (version-independent, content-addressed).
#
# The config scope is PER-VARIANT because the config.yaml lib.sh writes into it
# names a variant-specific build_stage. Sharing one scope means a login-node
# `pixi run fetch-spack` rewrites the build_stage out from under a cray build
# running on a compute node — the two disagree about where LOCALDIR is. The
# cache scope is Spack's own (bootstrap, etc.) and is fine to share.
export SPACK_ROOT="$STAGE1_DIR/vendor/spack"
export SPACK_USER_CONFIG_PATH="$LFRIC_PREFIX/spack-config/$LFRIC_STACK"
export SPACK_USER_CACHE_PATH="$LFRIC_PREFIX/spack-cache"
export LFRIC_SOURCE_CACHE="${LFRIC_SOURCE_CACHE:-$LFRIC_BASE/source-cache}"
export LFRIC_MISC_CACHE="${LFRIC_MISC_CACHE:-$LFRIC_BASE/misc-cache}"

# The Spack environment itself. The tracked spack-env/<variant>/spack.yaml is a
# TEMPLATE; lib.sh instantiates it under LFRIC_PREFIX so the view and lockfile
# land outside the repo.
export SPACK_ENV_TEMPLATE="$STAGE1_DIR/spack-env/$LFRIC_STACK/spack.yaml"
export SPACK_ENV_DIR="$LFRIC_PREFIX/spack-env/$LFRIC_STACK"
export ENV_NAME="lfric-apps-isambard-$LFRIC_STACK"

# The product. One shared modulefile tree keyed by version and variant, so a
# single `module use` makes `module avail lfric-env` list every build.
export MODULEFILES_DIR="$LFRIC_BASE/modulefiles"
export MODULE_NAME="lfric-env/$LFRIC_ENV_VERSION/$LFRIC_STACK"
export MODULEFILE="$MODULEFILES_DIR/lfric-env/$LFRIC_ENV_VERSION/$LFRIC_STACK.lua"

# Vendored `spack` on PATH, built modulefiles on MODULEPATH (both idempotent).
case ":${PATH:-}:" in
  *":$SPACK_ROOT/bin:"*) : ;;
  *) export PATH="$SPACK_ROOT/bin${PATH:+:$PATH}" ;;
esac
case ":${MODULEPATH:-}:" in
  *":$MODULEFILES_DIR:"*) : ;;
  *) export MODULEPATH="$MODULEFILES_DIR${MODULEPATH:+:$MODULEPATH}" ;;
esac

# Spack 1.0 parses sources with ast.Str, removed in CPython 3.12 — so it must run
# under Python in [3.7, 3.12). Supplying that is pixi's job (python = "3.11.*" in
# pixi.toml); pin Spack to the python3 pixi just put on PATH. lib.sh verifies the
# version, so a surprise here is a clear error rather than a Spack traceback.
if [ -z "${SPACK_PYTHON:-}" ] && command -v python3 >/dev/null 2>&1; then
  SPACK_PYTHON="$(command -v python3)"
fi
export SPACK_PYTHON
