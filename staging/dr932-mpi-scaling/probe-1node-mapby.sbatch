#!/bin/bash
#SBATCH --job-name=probe-1node-mapby
#SBATCH --partition=grace
#SBATCH --nodes=1
#SBATCH --ntasks=108
#SBATCH --cpus-per-task=1
#SBATCH --mem-per-cpu=1600M
#SBATCH --time=00:25:00
#SBATCH --output=staging/dr932-mpi-scaling/results/1node-mapby-%j.out
#
# results/1node-bound-*.out showed `-bind-to core` is not a free win: it fixes the ranks
# (108/108 pinned) and buys 1.5x on latency, but LOSES 23% of pairwise bandwidth against
# the unbound run -- 309 GB/s vs 402.
#
# Likely cause: Hydra fills cores linearly, so ranks 0-107 occupy cpus 0-107 and a Grace
# node is 2 sockets x 72 -- 72 ranks on socket 0, 36 on socket 1. Latency does not care;
# a bandwidth test on an unbalanced pair of memory controllers does. srun sidesteps it by
# alternating sockets (its 1-node run put rank 0 on cpu 0, rank 1 on cpu 72).
#
# Test the fix rather than assume it. If -map-by recovers the bandwidth while keeping the
# latency win, the recommendation to Denis needs it too, since his 108-ranks-on-144-cores
# hits exactly this.
set -uo pipefail
cd "${SLURM_SUBMIT_DIR:-$(pwd)}" || exit 1

for extra in "" "-map-by numa" "-map-by socket" "-map-by hwthread"; do
  echo "############ -bind-to core ${extra:-(linear fill)} ############"
  PROBE_MPIEXEC_EXTRA="$extra" timeout 600 \
    bash staging/dr932-mpi-scaling/run-probe.sh uoe mpiexec-bound 108 2>&1 \
    | grep -E "^--- exec|^PROBE (ranks|nodes|binding|allreduce|pairwise|ring)|^PROBE   rank [0-3] "
  echo "  rc=$?"
  echo
done
