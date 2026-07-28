#!/bin/bash
#SBATCH --job-name=probe-as-suite
#SBATCH --partition=grace
#SBATCH --time=00:20:00
#SBATCH --output=staging/dr932-mpi-scaling/results/as-suite-%j.out
#
# --- BELOW: copied verbatim from u-dr932's [[lfric_atm]][[[directives]]] for
# --- MACHINE == "isambard3-gnu", plus TOTAL_RANKS_REQ=108 from rose-suite.conf.
#SBATCH --mem-per-cpu=8G
#SBATCH --ntasks=108
#SBATCH --cpus-per-task=1
#SBATCH --export=NONE
#
# The reproduction. Runs the probe exactly as Denis' suite runs lfric_atm:
# the UoE stack's MPICH, launched by `mpiexec -n 108` (what upstream launch-exe
# emits when TARGET_PLATFORM is not meto-ex1a), inside the allocation those
# directives ask for.
#
#   sbatch staging/dr932-mpi-scaling/probe-as-suite.sbatch
set -uo pipefail
cd "${SLURM_SUBMIT_DIR:-$(pwd)}" || exit 1

echo "=== allocation granted for the suite's own directives"
echo "SLURM_JOB_NUM_NODES = ${SLURM_JOB_NUM_NODES:-?}   <-- 108 ranks fit on ONE 144-core node"
echo "SLURM_JOB_NODELIST  = ${SLURM_JOB_NODELIST:-?}"
echo "SLURM_TASKS_PER_NODE= ${SLURM_TASKS_PER_NODE:-?}"
echo "SLURM_MEM_PER_CPU   = ${SLURM_MEM_PER_CPU:-?} MB"
echo

timeout 600 bash staging/dr932-mpi-scaling/run-probe.sh uoe mpiexec 108
echo "exit=$?"
