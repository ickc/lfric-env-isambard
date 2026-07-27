#!/usr/bin/env bash
# model-run.sh <tag> [steps]
#
# Time the REAL model, not a microbenchmark. Takes the lfric_atm binary and the
# fully-materialised work directory that examples/science-suites/u-dr932 already
# produced on this env, re-runs it for <steps> timesteps under whatever placement
# the enclosing Slurm allocation provides, and reports the wall clock.
#
# Everything except the allocation is held constant -- same binary, same
# configuration.nml, same mesh -- so the difference between two <tag>s is the
# placement and nothing else. That is the point: Denis' suite asks Slurm for an
# allocation that scatters 108 ranks over up to 32 nodes (see README.md), and this
# shows what that costs the model.
#
# Requires: a previous `run-suite.sh u-dr932` run under $REF_RUN (override to point
# at your own). Run inside an allocation, via model-*.sbatch.
set -euo pipefail

tag="${1:?usage: model-run.sh <tag> [steps]}"
steps="${2:-300}"

here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd -- "$here/../.." && pwd)"

REF_RUN="${REF_RUN:-${PROJECTDIR:-/projects/u35v}/$USER/cylc-run/cylc-run/u-dr932/run1}"
REF_WORK="$REF_RUN/work/20000101T0000Z/lfric_atm"
EXE="$REF_RUN/share/output/bin/lfric_atm/lfric_atm"
[ -x "$EXE" ] || { echo "model-run.sh: no lfric_atm at $EXE -- run run-suite.sh u-dr932 first" >&2; exit 1; }

# shellcheck source=examples/science-suites/site/activate-env.sh
. "$repo/examples/science-suites/site/activate-env.sh"

# SHARED filesystem, not $LOCALDIR: a scattered run has ranks on a dozen nodes and
# every one of them must read configuration.nml from the same place.
rundir="${MODEL_RUN_DIR:-${PROJECTDIR:-${SCRATCH:-$HOME}}/$USER/dr932-model}/$tag-${SLURM_JOB_ID:-$$}"
mkdir -p "$rundir"
# Everything the model READS at run time: namelists and the XIOS xml. Deliberately
# not lfric_initial.nc -- that is an OUTPUT (io: write_initial=.true.), and leaving a
# copy of it in place makes XIOS' nc_create fail before the timestep loop starts.
cp "$REF_WORK"/*.nml "$REF_WORK"/*.xml "$rundir/"
cd "$rundir"

# Lustre rejects the flock() HDF5 wants; same workaround site/activate-env.sh applies.
export HDF5_USE_FILE_LOCKING=FALSE

# Run length: long enough that the timestep loop, not setup, dominates the wall clock.
sed -i "s/^timestep_end='[0-9]*',/timestep_end='$steps',/" configuration.nml
# Diagnostics off. We are measuring how PLACEMENT changes the cost of the dynamics'
# halo swaps and global sums, and XIOS output would put Lustre in the middle of that
# -- both as noise and, in attached mode across a dozen nodes, as an outright failure
# (racing nc_create on the same one_file). Identical in both arms, so the comparison
# is unaffected.
sed -i -e "s/^write_diag=.*/write_diag=.false.,/" \
       -e "s/^write_initial=.*/write_initial=.false.,/" \
       -e "s/^write_conservation_diag=.*/write_conservation_diag=.false.,/" configuration.nml
# ...and the per-timestep INFO log with it: at run_log_level='info' a few hundred steps
# emit tens of MB down one rank's stdout onto Lustre, which is both timing noise and an
# unreasonable thing to keep in results/.
sed -i "s/^run_log_level=.*/run_log_level='warning',/" configuration.nml
grep -E "^timestep_(start|end)=|^write_(diag|initial|conservation_diag)=|^run_log_level=" configuration.nml | sed 's/^/--- /'

echo "--- tag=$tag steps=$steps rundir=$rundir"
echo "--- SLURM_JOB_NUM_NODES=${SLURM_JOB_NUM_NODES:-?} SLURM_NTASKS=${SLURM_NTASKS:-?} SLURM_TASKS_PER_NODE=${SLURM_TASKS_PER_NODE:-?}"
echo "--- nodes: ${SLURM_JOB_NODELIST:-?}"

# Model stdout stays in the run dir; only the summary reaches results/.
t0=$(date +%s)
srun --ntasks="${SLURM_NTASKS:?}" "$EXE" configuration.nml > model.log 2>&1
rc=$?
t1=$(date +%s)
echo "--- last 15 lines of $rundir/model.log"
tail -15 model.log | sed 's/^/--- /'

echo "RESULT tag=$tag nodes=${SLURM_JOB_NUM_NODES:-?} ranks=${SLURM_NTASKS:-?} steps=$steps elapsed_s=$((t1 - t0)) rc=$rc"
if [ -f timer.txt ]; then
  echo "--- timer.txt (top sections by total time)"
  sed -n '1,25p' timer.txt
fi
exit $rc
