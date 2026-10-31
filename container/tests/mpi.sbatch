#!/bin/bash
#SBATCH --job-name=lfric-container-mpi
#SBATCH --partition=grace
#SBATCH --nodes=2
#SBATCH --ntasks-per-node=2
#SBATCH --time=00:30:00
#SBATCH --output=logs/container-mpi-%j.out
#
# The container's integration test on two nodes. Submit from the repo root:
#
#   LFRIC_CONTAINER_IMAGE=/path/to/lfric-env_<version>.sif sbatch --export=ALL container/tests/mpi.sbatch
#
# Checks, in order, everything container/README.md promises about running:
#   1. the image's own acceptance test (lfric-container-check);
#   2. compiling an mpi_f08 program with the container's toolchain;
#   3. srun from INSIDE the container, in each MPI mode (host cray-mpich,
#      host libfabric, the container's own MPICH), across the two nodes;
#   4. srun --multi-prog (what the science suites' launch-exe uses);
#   5. the host's sbatch from inside the container.
# Ends with CONTAINER_MPI_OK when all pass.
set -uo pipefail
cd "${SLURM_SUBMIT_DIR:-$(pwd)}" || exit 1
: "${LFRIC_CONTAINER_IMAGE:?set LFRIC_CONTAINER_IMAGE to the image (a .sif)}"
helper="$PWD/container/bin/lfric-container"
work="$PWD/logs/container-mpi-${SLURM_JOB_ID:-$$}"
mkdir -p "$work"
failed=0
step() { echo; echo "=== $*"; }
fail() { echo "FAIL: $*"; failed=1; }

step "1. lfric-container-check"
"$helper" exec lfric-container-check || fail "lfric-container-check"

step "2. compile container/tests/pingpong.f90 with \$FC"
"$helper" exec bash -c "cd '$work' && \$FC --version | head -1 && \$FC -O2 -o pingpong '$PWD/container/tests/pingpong.f90'" \
  || fail "compiling pingpong"

# One rank per node, so the ping-pong crosses the interconnect.
# expect: <mode> <library line pattern> <max latency in us>
while read -r mode lib maxlat; do
  step "3. srun, LFRIC_CONTAINER_MPI=$mode (expect: $lib, latency < $maxlat us)"
  # </dev/null: srun forwards stdin, and would eat this loop's here-document.
  out="$(LFRIC_CONTAINER_MPI=$mode "$helper" exec srun --ntasks=2 --ntasks-per-node=1 "$work/pingpong" 2>&1 </dev/null)"
  echo "$out"
  grep -q PINGPONG_OK <<< "$out" || { fail "$mode: no PINGPONG_OK"; continue; }
  grep -q "^library: .*$lib" <<< "$out" || fail "$mode: expected an MPI library matching '$lib'"
  lat="$(awk '/^latency/ { print $(NF-1) }' <<< "$out")"
  awk -v l="$lat" -v m="$maxlat" 'BEGIN { exit !(l < m) }' || fail "$mode: latency $lat us, expected < $maxlat"
done <<'EOF'
host CRAY 5
libfabric MPICH 5
none MPICH 100
EOF

step "4. srun --multi-prog, all four ranks"
printf '0-3 %s\n' "$work/pingpong" > "$work/multi.conf"
out="$("$helper" exec srun --multi-prog "$work/multi.conf" 2>&1 </dev/null)"
echo "$out"
grep -q 'ranks: 4' <<< "$out" && grep -q PINGPONG_OK <<< "$out" || fail "multi-prog"

step "5. sbatch --test-only from inside the container"
"$helper" exec sbatch --test-only --partition=grace --wrap=true 2>&1 | tee "$work/sbatch.out"
grep -q 'to start at' "$work/sbatch.out" || fail "sbatch from inside the container"

echo
if [ "$failed" = 0 ]; then echo CONTAINER_MPI_OK; else echo "CONTAINER_MPI_FAILED"; exit 1; fi
