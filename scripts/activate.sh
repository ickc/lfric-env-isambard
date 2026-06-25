#!/usr/bin/env bash
# Auto-load the built LFRic environment via Lmod — the one piece of activation
# pixi cannot do declaratively (an env var can't run `module load`). Sourced by
# pixi on every `pixi run` / `pixi shell` (see [activation] in pixi.toml), AFTER
# common.sh — which puts the generated modulefiles on MODULEPATH and sets
# LFRIC_STACK. So this stays a thin shim; the modulefile is the source of truth.
#
# Deliberately a NO-OP until the environment is built: `module load` of a
# not-yet-generated modulefile just fails quietly. End users without pixi do not
# need this script at all — they activate the same environment directly with:
#   module use "$PREFIX/modulefiles" && module load lfric-env/<variant>
#
# We do NOT source spack's setup-env.sh (its exported shell functions error
# noisily when pixi runs a command under /bin/sh); Lmod's `module` function is
# /bin/sh-safe, so we use it directly.

# pixi may source us under /bin/sh, which does not inherit the login shell's
# `module` function — initialize Lmod when absent (guarded so we never reset an
# already-set-up Lmod / its MODULEPATH in an interactive shell).
if ! command -v module >/dev/null 2>&1; then
  for f in /opt/cray/pe/lmod/lmod/init/sh /etc/profile.d/lmod.sh \
           /usr/share/lmod/lmod/init/sh /usr/share/lmod/lmod/init/bash; do
    # shellcheck source=/dev/null
    [ -f "$f" ] && . "$f" 2>/dev/null && break
  done
fi

# Load the variant selected by LFRIC_STACK (default cray). Quiet in this
# auto-activation path (mirrors the old silent snippet source); `pixi run
# activate` / build.sh surface any real problems loudly.
if command -v module >/dev/null 2>&1; then
  module load "lfric-env/${LFRIC_STACK:-cray}" 2>/dev/null || true
fi
