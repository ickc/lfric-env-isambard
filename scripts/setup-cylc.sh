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

# isambard3 Slurm platform (written once; edit by hand thereafter).
plat_dir="$conf_dir/platforms.d"
plat_file="$plat_dir/isambard3.cylc"
mkdir -p "$plat_dir" || die "could not create $plat_dir (permissions? full filesystem?)"
if [ ! -f "$plat_file" ]; then
  cat > "$plat_file" <<EOF
$plat_start
[platforms]
    [[isambard3]]
        hosts = localhost
        job runner = slurm
        install target = localhost
$plat_end
EOF
  info "isambard3 platform -> $plat_file"
else
  info "isambard3 platform already exists: $plat_file (left as-is)"
fi

echo "CYLC_SETUP_OK"
