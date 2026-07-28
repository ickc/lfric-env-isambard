#!/bin/bash
#SBATCH --job-name=probe-1node
#SBATCH --partition=grace
#SBATCH --nodes=1
#SBATCH --ntasks=108
#SBATCH --cpus-per-task=1
#SBATCH --mem-per-cpu=1600M
#SBATCH --time=00:30:00
#SBATCH --output=staging/dr932-mpi-scaling/results/1node-%j.out
#
# Control A: the placement the suite SHOULD get -- 108 ranks on one 144-core Grace
# node. --mem-per-cpu=1600M is the node's true per-core share (230400 MB / 144).
# Both stacks are measured here, so the numbers isolate transport/binding from
# placement.
#
#   sbatch staging/dr932-mpi-scaling/probe-1node.sbatch
set -uo pipefail
cd "${SLURM_SUBMIT_DIR:-$(pwd)}" || exit 1

echo "SLURM_JOB_NUM_NODES=${SLURM_JOB_NUM_NODES:-?} NODELIST=${SLURM_JOB_NODELIST:-?}"
echo

for spec in "uoe mpiexec" "cray srun" "cray mpiexec"; do
  set -- $spec
  echo "############ $1 / $2 ############"
  timeout 600 bash staging/dr932-mpi-scaling/run-probe.sh "$1" "$2" 108
  echo "exit=$?"
  echo
done
