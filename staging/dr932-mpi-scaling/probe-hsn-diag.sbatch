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

echo "=== interfaces + LINK SPEED, per node ==="
# The speed is the point: on the login node bond0 is a single 1 GbE slave (eno1) while
# hsn0 is 200 Gb/s. If that holds on compute nodes, the TCP fallback is not merely
# "slower", it is saturating a link 200x narrower than the one sitting idle next to it.
srun --ntasks="${SLURM_JOB_NUM_NODES}" --ntasks-per-node=1 bash -c '
  for i in /sys/class/net/*/; do n=$(basename "$i"); [ "$n" = lo ] && continue
    printf "[%s] %-12s speed=%-8s addr=%s\n" "$(hostname)" "$n" \
      "$(cat "$i/speed" 2>/dev/null || echo -)" \
      "$(ip -br addr show "$n" | awk "{print \$3}")"
  done
  for b in /sys/class/net/bond*/bonding/slaves; do
    [ -r "$b" ] && echo "[$(hostname)] $(echo "$b" | cut -d/ -f5) slaves=[$(cat "$b")]"
  done'

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
