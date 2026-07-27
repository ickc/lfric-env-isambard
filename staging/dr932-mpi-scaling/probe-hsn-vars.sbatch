#!/bin/bash
#SBATCH --job-name=probe-hsn-vars
#SBATCH --partition=grace
#SBATCH --nodes=2
#SBATCH --ntasks=4
#SBATCH --ntasks-per-node=2
#SBATCH --cpus-per-task=1
#SBATCH --mem-per-cpu=1600M
#SBATCH --time=00:20:00
#SBATCH --output=staging/dr932-mpi-scaling/results/hsn-vars-%j.out
#
# Third attempt at the hsn0 thread, after two hypotheses died:
#   - "hsn0 is absent/down on compute nodes"      -> no, it is up, addressed, 200000 Mb/s
#   - "node-to-node IP is not carried over hsn0"  -> no, ping is 0.04 ms, FASTER than bond0
# so MPICH refusing MPIR_CVAR_NEMESIS_TCP_NETWORK_IFACE=hsn0 is neither. What is left is
# how the cvar is spelled and what it does to the business card each rank publishes.
# MPICH's own strings in this libmpi mention several names for the same knob, and the
# error text refers to a DIFFERENT one than the cvar description does:
#   MPIR_CVAR_NEMESIS_TCP_NETWORK_IFACE / MPICH_NEMESIS_TCP_NETWORK_IFACE
#   MPIR_CVAR_NETWORK_IFACE / MPICH_NETWORK_IFACE
#   MPIR_CVAR_CH3_INTERFACE_HOSTNAME  (mutually exclusive with the above; takes an ADDRESS)
#   ... while the failure message names MPIR_CVAR_CH3_NETWORK_IFACE
#
# Each variant runs the probe on 4 ranks across 2 nodes with stderr merged. A working
# variant prints PROBE lines; a broken one exits non-zero. Also proves L4 (not just ICMP)
# reachability over hsn0 first, using python rather than nc, which is not installed.
set -uo pipefail
cd "${SLURM_SUBMIT_DIR:-$(pwd)}" || exit 1

mapfile -t nodes < <(scontrol show hostnames "$SLURM_JOB_NODELIST")
a="${nodes[0]}"; b="${nodes[1]}"
bip=$(srun --nodes=1 --nodelist="$b" --ntasks=1 bash -c 'ip -br addr show hsn0 | awk "{print \$3}"' 2>/dev/null)
bip="${bip%%/*}"
echo "nodes: $a $b   (b hsn0=$bip)"

echo
echo "=== TCP (not just ICMP) over hsn0, python ==="
srun --nodes=1 --nodelist="$b" --ntasks=1 python3 -c "
import socket
s=socket.socket(); s.setsockopt(socket.SOL_SOCKET,socket.SO_REUSEADDR,1)
s.bind(('0.0.0.0',9999)); s.listen(1); s.settimeout(30)
c,addr=s.accept(); print('listener: accepted from',addr, flush=True); c.close()" &
sleep 6
srun --nodes=1 --nodelist="$a" --ntasks=1 python3 -c "
import socket,sys
try:
    s=socket.create_connection(('$bip',9999),timeout=10); print('connector: TCP to $bip:9999 OK'); s.close()
except Exception as e:
    print('connector: FAILED', e); sys.exit(1)"
echo "  connect rc=$?"
wait

E=staging/dr932-mpi-scaling/build/mpi-probe.uoe
for spec in \
  "BASELINE:" \
  "MPIR_CVAR_NEMESIS_TCP_NETWORK_IFACE:MPIR_CVAR_NEMESIS_TCP_NETWORK_IFACE=hsn0" \
  "MPICH_NEMESIS_TCP_NETWORK_IFACE:MPICH_NEMESIS_TCP_NETWORK_IFACE=hsn0" \
  "MPIR_CVAR_NETWORK_IFACE:MPIR_CVAR_NETWORK_IFACE=hsn0" \
  "MPIR_CVAR_CH3_NETWORK_IFACE:MPIR_CVAR_CH3_NETWORK_IFACE=hsn0" \
  ; do
  name="${spec%%:*}"; var="${spec#*:}"
  echo
  echo "############ $name ############"
  ( module purge >/dev/null 2>&1
    source /projects/u35v/sw/UoEGCC1120SWstackBuild/RoseStemSource.sh >/dev/null 2>&1
    # `env NAME=value` rather than export, so the baseline's empty $var is a clean no-op.
    timeout 180 env ${var:+"$var"} mpiexec -n 4 "$E" 2>&1 | grep -vE '^PROBE   rank' | head -12 )
  echo "  rc=$?"
done
