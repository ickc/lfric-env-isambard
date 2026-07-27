/* mpi-probe.c -- minimal MPI probe for the u-dr932 scaling investigation.
 *
 * Reports the three things that decide whether an LFRic run scales on Isambard 3,
 * without needing LFRic itself:
 *
 *   1. PLACEMENT  how many nodes the allocation actually spans, and how many ranks
 *                 landed on each. (Denis' suite asks for --mem-per-cpu=8G, which
 *                 caps a 225 GB node at 28 ranks and silently fans the job out.)
 *   2. BINDING    each rank's CPU affinity mask. A mask wider than one CPU means the
 *                 launcher did not pin the rank; the kernel is then free to migrate
 *                 it across the 2 NUMA sockets of a Grace superchip.
 *   3. TRANSPORT  MPI_Allreduce latency (LFRic's iterative solver does a global sum
 *                 per iteration) and cross-node pairwise bandwidth (halo swaps).
 *                 Slingshot/cxi RDMA vs a TCP fallback differ by ~an order of
 *                 magnitude here.
 *
 * Deliberately plain C99 + MPI-1 so it builds with any of the stacks under test
 * (UoE MPICH ch3:nemesis via mpicc, our cray-mpich via cc, our spack mpich via
 * mpicc). Build+run through ./run-probe.sh; see README.md.
 */
#define _GNU_SOURCE
#include <mpi.h>
#include <sched.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#define HOSTLEN 64
#define MASKLEN 96

/* Render this rank's CPU affinity as "lo-hi" (or "lo-hi,lo-hi" style is overkill
 * here: we only need the width, plus the first CPU, to tell bound from unbound). */
static int affinity_summary(char *out, size_t n)
{
    cpu_set_t set;
    int i, first = -1, last = -1, count = 0, ncpu = (int)sysconf(_SC_NPROCESSORS_CONF);

    CPU_ZERO(&set);
    if (sched_getaffinity(0, sizeof(set), &set) != 0) {
        snprintf(out, n, "?");
        return -1;
    }
    for (i = 0; i < ncpu && i < CPU_SETSIZE; i++) {
        if (CPU_ISSET(i, &set)) {
            if (first < 0) first = i;
            last = i;
            count++;
        }
    }
    snprintf(out, n, "%d-%d", first, last);
    return count;
}

static double now(void) { return MPI_Wtime(); }

int main(int argc, char **argv)
{
    int rank, size, i, iter;
    char host[HOSTLEN], mask[MASKLEN];
    double t0, t1;

    MPI_Init(&argc, &argv);
    MPI_Comm_rank(MPI_COMM_WORLD, &rank);
    MPI_Comm_size(MPI_COMM_WORLD, &size);

    gethostname(host, sizeof(host));
    host[HOSTLEN - 1] = '\0';
    int nbound = affinity_summary(mask, sizeof(mask));

    /* ---- 1+2. placement and binding ------------------------------------- */
    char *hosts = NULL, *masks = NULL;
    int *bounds = NULL;
    if (rank == 0) {
        hosts  = malloc((size_t)size * HOSTLEN);
        masks  = malloc((size_t)size * MASKLEN);
        bounds = malloc((size_t)size * sizeof(int));
    }
    MPI_Gather(host, HOSTLEN, MPI_CHAR, hosts, HOSTLEN, MPI_CHAR, 0, MPI_COMM_WORLD);
    MPI_Gather(mask, MASKLEN, MPI_CHAR, masks, MASKLEN, MPI_CHAR, 0, MPI_COMM_WORLD);
    MPI_Gather(&nbound, 1, MPI_INT, bounds, 1, MPI_INT, 0, MPI_COMM_WORLD);

    if (rank == 0) {
        printf("PROBE ranks=%d\n", size);
        /* unique hosts, in first-seen order, with rank counts */
        int nhosts = 0, unbound = 0;
        char *uniq = malloc((size_t)size * HOSTLEN);
        int *cnt = calloc((size_t)size, sizeof(int));
        for (i = 0; i < size; i++) {
            const char *h = hosts + (size_t)i * HOSTLEN;
            int j;
            for (j = 0; j < nhosts; j++)
                if (strcmp(uniq + (size_t)j * HOSTLEN, h) == 0) break;
            if (j == nhosts) { strcpy(uniq + (size_t)j * HOSTLEN, h); nhosts++; }
            cnt[j]++;
            if (bounds[i] != 1) unbound++;
        }
        printf("PROBE nodes=%d\n", nhosts);
        for (i = 0; i < nhosts; i++)
            printf("PROBE node %-20s ranks=%d\n", uniq + (size_t)i * HOSTLEN, cnt[i]);
        printf("PROBE binding: %d/%d ranks pinned to exactly 1 CPU (%s)\n",
               size - unbound, size, unbound ? "UNBOUND -- ranks can migrate" : "bound");
        for (i = 0; i < (size < 8 ? size : 8); i++)
            printf("PROBE   rank %-4d %-20s cpus=%s (width=%d)\n", i,
                   hosts + (size_t)i * HOSTLEN, masks + (size_t)i * MASKLEN, bounds[i]);
        free(uniq); free(cnt); free(hosts); free(masks); free(bounds);
        fflush(stdout);
    }

    /* ---- 3a. collective latency (the solver's global sums) --------------- */
    double val = 1.0, sum;
    const int NW = 200, NIT = 2000;
    for (iter = 0; iter < NW; iter++) MPI_Allreduce(&val, &sum, 1, MPI_DOUBLE, MPI_SUM, MPI_COMM_WORLD);
    MPI_Barrier(MPI_COMM_WORLD);
    t0 = now();
    for (iter = 0; iter < NIT; iter++) MPI_Allreduce(&val, &sum, 1, MPI_DOUBLE, MPI_SUM, MPI_COMM_WORLD);
    t1 = now();
    if (rank == 0)
        printf("PROBE allreduce_8B_usec %.2f\n", (t1 - t0) * 1e6 / NIT);

    /* ---- 3b. pairwise bandwidth (halo swaps) ----------------------------- */
    /* Pair rank r with r+size/2. When the job spans nodes with a block
     * distribution every pair straddles a node boundary, so this measures the
     * interconnect, not shared memory. */
    const size_t MSG = 1u << 20;   /* 1 MiB, the order of an LFRic halo buffer */
    const int NBW = 200;
    char *sbuf = malloc(MSG), *rbuf = malloc(MSG);
    memset(sbuf, 1, MSG);
    int half = size / 2, peer = (rank < half) ? rank + half : rank - half;
    int active = (size >= 2) && (peer < size);

    MPI_Barrier(MPI_COMM_WORLD);
    t0 = now();
    if (active)
        for (iter = 0; iter < NBW; iter++)
            MPI_Sendrecv(sbuf, (int)MSG, MPI_BYTE, peer, 0,
                         rbuf, (int)MSG, MPI_BYTE, peer, 0,
                         MPI_COMM_WORLD, MPI_STATUS_IGNORE);
    MPI_Barrier(MPI_COMM_WORLD);
    t1 = now();
    if (rank == 0) {
        double secs = t1 - t0;
        int pairs = half * 2;
        double gb = (double)pairs * (double)NBW * (double)MSG / 1e9;
        printf("PROBE pairwise_1MiB_aggregate_GBps %.2f  (%d ranks exchanging, %.2fs)\n",
               gb / secs, pairs, secs);
    }

    /* ---- 3c. ring halo exchange (nearest-neighbour, small message) ------- */
    const size_t HMSG = 64u << 10;
    const int NH = 2000;
    int left = (rank - 1 + size) % size, right = (rank + 1) % size;
    MPI_Barrier(MPI_COMM_WORLD);
    t0 = now();
    for (iter = 0; iter < NH; iter++)
        MPI_Sendrecv(sbuf, (int)HMSG, MPI_BYTE, right, 1,
                     rbuf, (int)HMSG, MPI_BYTE, left, 1,
                     MPI_COMM_WORLD, MPI_STATUS_IGNORE);
    MPI_Barrier(MPI_COMM_WORLD);
    t1 = now();
    if (rank == 0)
        printf("PROBE ring_64KiB_usec %.2f\n", (t1 - t0) * 1e6 / NH);

    free(sbuf); free(rbuf);
    if (rank == 0) { printf("PROBE done\n"); fflush(stdout); }
    MPI_Finalize();
    return 0;
}
