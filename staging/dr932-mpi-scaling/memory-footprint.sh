#!/usr/bin/env bash
# memory-footprint.sh [jobid ...]
#
# Does packing the ranks onto fewer nodes starve them of memory?
#
# The suite asks for --mem-per-cpu=8G, so 108 ranks reserve 864 GB -- nearly four
# whole Grace nodes' worth (a node is 230400 MB / 144 cores = 225 GB). If that is a
# real requirement then packing the job onto one node is not just wrong, it OOMs, and
# the placement fix has to respect it by capping ranks-per-node instead. So measure it.
#
# Reads Slurm accounting for completed lfric_atm jobs and converts MaxRSS to a per-rank
# figure. Two things make that conversion necessary rather than obvious:
#
#   * JobAcctGatherType is jobacct_gather/cgroup, and under Hydra the only things Slurm
#     launches are one hydra_pmi_proxy per node -- NTasks in the accounting equals
#     NNodes, not 108. The MPI ranks are descendants inside the same per-node cgroup.
#     So MaxRSS is the largest PER-NODE total, not a per-rank figure.
#   * That reading is testable: the rank count is 108 in every job, so a per-rank number
#     would be constant across them. It is not -- it tracks ranks-per-node, which is
#     what a per-node aggregate does.
#
# Caveat worth keeping: JobAcctGatherFrequency is 30 s, so a short allocation spike
# between samples is not captured. Sustained use over a 5-9 h job is.
#
# Defaults to the six completed cycles of Denis' dhj/c48_l66_s0p5_et. Pass other job ids
# to re-run this for a different configuration -- and DO re-run it before assuming the
# same headroom at higher resolution than C48_MG/L66.
set -uo pipefail

RANKS="${RANKS:-108}"
NODE_GB="${NODE_GB:-225}"
jobs=("${@:-5537502 5524896 5516605 5532814 5520538 5541962}")
# shellcheck disable=SC2206  # deliberate word-split of the default list
jobs=(${jobs[*]})

printf '%-10s %6s %11s %10s %10s %14s\n' JOB NODES RANKS/NODE MaxRSS MB/RANK "${RANKS}ranks->GB"
for id in "${jobs[@]}"; do
  read -r nnodes rss <<<"$(sacct -j "$id.0" -n -P -o NNodes,MaxRSS | head -1 | tr '|' ' ' | tr -d 'K')"
  [ -n "${rss:-}" ] || { echo "$id: no accounting"; continue; }
  RANKS="$RANKS" python3 -c "
import os,sys
n=float('$nnodes'); rss=float('$rss')/1024.0; ranks=float(os.environ['RANKS'])
rpn=ranks/n
print('%-10s %6d %11.1f %9.0fMB %10.0f %14.1f' % ('$id', n, rpn, rss, rss/rpn, rss/rpn*ranks/1024))"
done

echo
echo "requested: $(sacct -j "${jobs[0]}" -n -P -o ReqMem | head -1)   available on one node: ${NODE_GB} GB"
