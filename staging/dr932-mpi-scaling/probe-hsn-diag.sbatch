#!/bin/bash
#SBATCH --job-name=probe-hsn-diag
#SBATCH --partition=grace
#SBATCH --nodes=2
#SBATCH --ntasks=4
#SBATCH --ntasks-per-node=2
#SBATCH --cpus-per-task=1
#SBATCH --mem-per-cpu=1600M
#SBATCH --time=00:15:00
#SBATCH --output=staging/dr932-mpi-scaling/results/hsn-diag-%j.out
#
# Why MPIR_CVAR_NEMESIS_TCP_NETWORK_IFACE=hsn0 did not work (results/2node-hsn-*.out:
# the second arm produced no output and exited 15). Small and fast so it schedules
# promptly. Establishes, in order: does hsn0 exist on a compute node and carry an
# address; does MPICH start at all with the cvar set; and what does it say if not.
#
#   sbatch staging/dr932-mpi-scaling/probe-hsn-diag.sbatch
set -uo pipefail
cd "${SLURM_SUBMIT_DIR:-$(pwd)}" || exit 1

echo "=== interfaces, per node ==="
srun --ntasks="${SLURM_JOB_NUM_NODES}" --ntasks-per-node=1 \
     bash -c 'echo "[$(hostname)] $(ip -br addr | tr "\n" "|")"'

echo
echo "=== hostname resolution, per node ==="
srun --ntasks="${SLURM_JOB_NUM_NODES}" --ntasks-per-node=1 \
     bash -c 'echo "[$(hostname)] resolves to $(getent hosts "$(hostname)" | awk "{print \$1}")"'

echo
echo "=== MPICH with the cvar set (stderr merged, 4 ranks) ==="
PROBE_TCP_IFACE=hsn0 timeout 300 bash staging/dr932-mpi-scaling/run-probe.sh uoe mpiexec 4 2>&1
echo "exit=$?"

echo
echo "=== same, cvar unset, as the control ==="
timeout 300 bash staging/dr932-mpi-scaling/run-probe.sh uoe mpiexec 4 2>&1
echo "exit=$?"
