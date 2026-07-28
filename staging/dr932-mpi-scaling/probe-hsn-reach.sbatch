#!/bin/bash
#SBATCH --job-name=probe-hsn-reach
#SBATCH --partition=grace
#SBATCH --nodes=2
#SBATCH --ntasks=2
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=1
#SBATCH --mem-per-cpu=1600M
#SBATCH --time=00:10:00
#SBATCH --output=staging/dr932-mpi-scaling/results/hsn-reach-%j.out
#
# Closing out the hsn0 thread. results/hsn-diag-*.out established that hsn0 exists on
# compute nodes, carries a 10.243/16 address and reports 200000 Mb/s, and that MPICH
# still dies (exit 15, silently) when told to use it. The remaining question is whether
# ORDINARY IP TRAFFIC works between nodes over hsn0 at all: Slingshot's native path is
# kfabric/libfabric at kernel level (that is how Lustre reaches @kfi), and the IP
# interface existing does not by itself mean TCP between nodes is carried.
#
# If plain ping/TCP over 10.243 fails, MPICH's silence is explained -- it advertised an
# address its peers cannot reach -- and the cvar is a dead end rather than a bug.
#
#   sbatch staging/dr932-mpi-scaling/probe-hsn-reach.sbatch
set -uo pipefail
cd "${SLURM_SUBMIT_DIR:-$(pwd)}" || exit 1

mapfile -t nodes < <(scontrol show hostnames "$SLURM_JOB_NODELIST")
echo "nodes: ${nodes[*]}"

# hsn0 address of each node
for n in "${nodes[@]}"; do
  addr=$(srun --nodelist="$n" --ntasks=1 bash -c 'ip -br addr show hsn0 | awk "{print \$3}"' 2>/dev/null)
  echo "  $n hsn0=$addr"
  eval "hsn_${n//[^a-zA-Z0-9]/_}=${addr%%/*}"
done

a="${nodes[0]}"; b="${nodes[1]}"
bvar="hsn_${b//[^a-zA-Z0-9]/_}"
bip="${!bvar}"
echo
echo "=== ICMP over hsn0: $a -> $bip ==="
srun --nodelist="$a" --ntasks=1 ping -c 3 -W 3 "$bip" 2>&1 | sed 's/^/  /'
echo "  rc=$?"

echo
echo "=== ICMP over bond0 (the interface MPICH actually uses), for contrast ==="
srun --nodelist="$a" --ntasks=1 ping -c 3 -W 3 "$b" 2>&1 | sed 's/^/  /'
echo "  rc=$?"

echo
echo "=== TCP over hsn0: listener on $b:9999, connect from $a ==="
srun --nodelist="$b" --ntasks=1 bash -c "timeout 20 nc -l -p 9999 > /dev/null" &
sleep 5
srun --nodelist="$a" --ntasks=1 bash -c "echo hello | timeout 10 nc -w 5 $bip 9999" 2>&1 | sed 's/^/  /'
echo "  connect rc=$?"
wait
