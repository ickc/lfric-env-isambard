#!/bin/bash
#SBATCH --job-name=probe-2node-hsn
#SBATCH --partition=grace
#SBATCH --nodes=2
#SBATCH --ntasks=108
#SBATCH --ntasks-per-node=54
#SBATCH --cpus-per-task=1
#SBATCH --mem-per-cpu=1600M
#SBATCH --time=00:30:00
#SBATCH --output=staging/dr932-mpi-scaling/results/2node-hsn-%j.out
#
# How much of the TCP penalty is fixable WITHOUT rebuilding the MPI.
#
# nemesis:tcp chooses its interface by resolving the local hostname, and on Isambard 3
# a compute node's name resolves to its 172.23/16 management address (bond0) -- so the
# fallback traffic is not merely TCP, it is TCP on the admin network. hsn0 (10.243/16)
# is the Slingshot NIC's IP interface. MPIR_CVAR_NEMESIS_TCP_NETWORK_IFACE moves the
# sockets there. Still no RDMA -- it is the kernel TCP stack either way -- but over the
# right wire. Compare against the `uoe / mpiexec` rows in results/2node-*.out, which are
# the identical run with this unset.
#
#   sbatch staging/dr932-mpi-scaling/probe-2node-hsn.sbatch
set -uo pipefail
cd "${SLURM_SUBMIT_DIR:-$(pwd)}" || exit 1

echo "SLURM_JOB_NUM_NODES=${SLURM_JOB_NUM_NODES:-?} NODELIST=${SLURM_JOB_NODELIST:-?}"
echo "hostname -> $(getent hosts "$(hostname)")   (the address nemesis:tcp defaults to)"
echo

echo "############ uoe / mpiexec / default iface (management) ############"
timeout 900 bash staging/dr932-mpi-scaling/run-probe.sh uoe mpiexec 108
echo "exit=$?"
echo
echo "############ uoe / mpiexec / MPIR_CVAR_NEMESIS_TCP_NETWORK_IFACE=hsn0 ############"
PROBE_TCP_IFACE=hsn0 timeout 900 bash staging/dr932-mpi-scaling/run-probe.sh uoe mpiexec 108
echo "exit=$?"
