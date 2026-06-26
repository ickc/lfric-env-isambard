#!/usr/bin/env bash
# setup-cylc.sh — configure cylc for running suites on Isambard 3.
#
# This is OPT-IN and OPTIONAL. It writes two files in your HOME, idempotently:
#   ~/.cylc/flow/global.cylc            a [symlink dirs] run directory
#   ~/.cylc/flow/platforms.d/isambard3.cylc   an `isambard3` Slurm platform
#
# It is NOT part of building the environment (Stage 1) — building must not touch
# your home dir — and the bundled lfric_atm example does not need it (it runs the
# binary directly). Run it only when you want to drive rose/cylc workflows.
#
#   bash scripts/setup-cylc.sh
#
# Overridable: CYLC_RUN_BASE (the run directory; default
# $PROJECTDIR/$USER/cylc-run), CYLC_USER_CONF (default ~/.cylc/flow/global.cylc).
set -uo pipefail

info() { echo "INFO: $*"; }
warn() { echo "WARN: $*" >&2; }
die()  { echo "ERROR: $*" >&2; exit 1; }

run_base_root="${CYLC_RUN_BASE_ROOT:-${PROJECTDIR:-${SCRATCH:-$HOME}}}"
run_base="${CYLC_RUN_BASE:-$run_base_root/${USER}/cylc-run}"
conf="${CYLC_USER_CONF:-$HOME/.cylc/flow/global.cylc}"
conf_dir="$(dirname "$conf")"
run_start="# BEGIN LFRIC_CYLC_RUN_DIR";   run_end="# END LFRIC_CYLC_RUN_DIR"
plat_start="# BEGIN LFRIC_ISAMBARD3_PLATFORM"; plat_end="# END LFRIC_ISAMBARD3_PLATFORM"

mkdir -p "$conf_dir" "$run_base" \
  || die "could not create $conf_dir / $run_base (permissions? full filesystem?)"
[ -f "$conf" ] || : > "$conf" || die "could not write $conf"

# Run directory: replace our managed block if present, else append it.
if grep -q "$run_start" "$conf" 2>/dev/null; then
  awk -v s="$run_start" -v e="$run_end" -v run="$run_base" '
    $0==s {inb=1; print; print "[install]"; print "    [[symlink dirs]]";
           print "        [[[localhost]]]"; print "            run = " run; next}
    $0==e {inb=0; print; next} !inb{print}' "$conf" > "$conf.tmp" && mv "$conf.tmp" "$conf"
else
  cat >> "$conf" <<EOF

$run_start
[install]
    [[symlink dirs]]
        [[[localhost]]]
            run = $run_base
$run_end
EOF
fi
info "cylc run dir -> $run_base  (in $conf)"

# isambard3 Slurm platform. This MUST go in global.cylc itself: the `platforms.d/`
# drop-in directory is only read by cylc >= 8.5, but the environment ships cylc
# 8.4.2 — which reads platforms ONLY from global.cylc. Write it as a managed block
# (replace if present, else append), mirroring the run-dir block above.
if grep -q "$plat_start" "$conf" 2>/dev/null; then
  awk -v s="$plat_start" -v e="$plat_end" '
    $0==s {inb=1; print; print "[platforms]"; print "    [[isambard3]]";
           print "        hosts = localhost"; print "        job runner = slurm";
           print "        install target = localhost"; next}
    $0==e {inb=0; print; next} !inb{print}' "$conf" > "$conf.tmp" && mv "$conf.tmp" "$conf"
else
  cat >> "$conf" <<EOF

$plat_start
[platforms]
    [[isambard3]]
        hosts = localhost
        job runner = slurm
        install target = localhost
$plat_end
EOF
fi
info "isambard3 platform -> $conf"

# Remove a stale platforms.d/isambard3.cylc from older setup-cylc.sh runs: cylc
# 8.4.2 ignores it, and leaving it is confusing once the platform lives in
# global.cylc. (Only our managed file; harmless if absent.)
stale_plat="$conf_dir/platforms.d/isambard3.cylc"
if [ -f "$stale_plat" ] && grep -q "$plat_start" "$stale_plat" 2>/dev/null; then
  rm -f "$stale_plat"
  rmdir "$conf_dir/platforms.d" 2>/dev/null || true
fi

echo "CYLC_SETUP_OK"
