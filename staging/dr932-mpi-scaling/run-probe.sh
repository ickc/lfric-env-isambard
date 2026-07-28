#!/usr/bin/env bash
# run-probe.sh <stack> <launcher> [ranks]
#
# Build and run mpi-probe.c against ONE of the MPI stacks in play, launched the way
# the corresponding suite launches lfric_atm. Run this INSIDE a Slurm allocation
# (it is driven by probe.sbatch); the allocation is what decides node placement.
#
#   stack     uoe    the environment Denis' suite sources -- /projects/u35v/sw/
#                    UoEGCC1120SWstackBuild/RoseStemSource.sh, whose MPI is a
#                    from-source MPICH 4.2.3 built --with-device=ch3 (ch3:nemesis).
#             cray   this repo's `cray` variant (cray-mpich + Slingshot/cxi).
#             spack  this repo's `spack` variant (from-source mpich, ch4:ofi).
#
#   launcher  mpiexec  what upstream launch-exe emits for a non-meto TARGET_PLATFORM:
#                      a bare `mpiexec -n $TOTAL_RANKS ...` -- no --ppn, no binding.
#             mpiexec-bound  the same Hydra launch with `-bind-to core -ppn <ranks>`,
#                      i.e. the cheapest fix available without changing MPI stack.
#             srun     what examples/science-suites/site/bin/launch-exe emits.
#
# Prints the PROBE lines to stdout; probe.sbatch tees them into results/.
set -euo pipefail

stack="${1:?usage: run-probe.sh <uoe|cray|spack> <mpiexec|srun> [ranks]}"
launcher="${2:?usage: run-probe.sh <uoe|cray|spack> <mpiexec|srun> [ranks]}"
ranks="${3:-${SLURM_NTASKS:-4}}"

here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd -- "$here/../.." && pwd)"
out="${PROBE_BUILD_DIR:-$here/build}"
mkdir -p "$out"
exe="$out/mpi-probe.$stack"

# --- select the stack ------------------------------------------------------
case "$stack" in
  uoe)
    # Exactly what the suite's ISAMBARD3GNU pre-script does.
    module purge >/dev/null 2>&1 || true
    # shellcheck source=/dev/null
    source /projects/u35v/sw/UoEGCC1120SWstackBuild/RoseStemSource.sh >/dev/null
    CC_MPI=mpicc
    # This MPICH's only inter-node netmod is nemesis:tcp, which picks its interface by
    # resolving the local hostname -- and a compute node's name resolves to its 172.23/16
    # MANAGEMENT address (bond0), not to hsn0, the Slingshot NIC's IP interface. Setting
    # PROBE_TCP_IFACE=hsn0 moves that TCP onto the fast NIC without rebuilding anything.
    if [ -n "${PROBE_TCP_IFACE:-}" ]; then
      export MPIR_CVAR_NEMESIS_TCP_NETWORK_IFACE="$PROBE_TCP_IFACE"
      echo "--- MPIR_CVAR_NEMESIS_TCP_NETWORK_IFACE=$MPIR_CVAR_NEMESIS_TCP_NETWORK_IFACE"
    fi
    ;;
  cray|spack)
    # shellcheck source=/dev/null
    LFRIC_STACK="$stack" source "$repo/scripts/common.sh"
    module use "$MODULEFILES_DIR"
    module load "$MODULE_NAME"
    if [ "$stack" = cray ]; then CC_MPI=cc; else CC_MPI=mpicc; fi
    ;;
  *) echo "run-probe.sh: unknown stack '$stack'" >&2; exit 2 ;;
esac

echo "=== stack=$stack launcher=$launcher ranks=$ranks"
echo "--- $CC_MPI -> $(command -v "$CC_MPI" || echo MISSING)"
command -v mpichversion >/dev/null 2>&1 && mpichversion | sed 's/^/--- /' || true

# --- build -----------------------------------------------------------------
"$CC_MPI" -O2 -std=gnu99 -o "$exe" "$here/mpi-probe.c"
echo "--- linked against:"
ldd "$exe" | grep -Ei 'mpi|fabric|pmi|ucx' | sed 's/^/---   /' || true

# --- launch ----------------------------------------------------------------
case "$launcher" in
  mpiexec)
    # Reproduces upstream launch-exe's non-meto branch verbatim: LAUNCHER_OPTS="-n N".
    echo "--- exec: mpiexec -n $ranks $exe"
    mpiexec -n "$ranks" "$exe"
    ;;
  mpiexec-bound)
    ppn="${PROBE_PPN:-$ranks}"
    # PROBE_MPIEXEC_EXTRA carries e.g. `-map-by numa`. `-bind-to core` alone fills the
    # cores linearly, so 108 ranks land 72 on socket 0 and 36 on socket 1 of a 2x72 Grace
    # node -- fine for latency, bad for a bandwidth test. srun balances by default.
    extra="${PROBE_MPIEXEC_EXTRA:-}"
    # shellcheck disable=SC2086  # $extra is a deliberate multi-word flag list
    echo "--- exec: mpiexec -bind-to core $extra -ppn $ppn -n $ranks $exe"
    # shellcheck disable=SC2086
    mpiexec -bind-to core $extra -ppn "$ppn" -n "$ranks" "$exe"
    ;;
  srun)
    echo "--- exec: srun --ntasks=$ranks $exe"
    srun --ntasks="$ranks" "$exe"
    ;;
  *) echo "run-probe.sh: unknown launcher '$launcher'" >&2; exit 2 ;;
esac
