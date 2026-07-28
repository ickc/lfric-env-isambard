# `staging/` — investigations

Self-contained investigations: enough committed material to **reproduce** a reported
problem from scratch, plus the evidence and the conclusion. Neither the reproducible
core (Stage 1) nor a science-suite example — nothing here is on the build invariant,
and `scripts/`, `spack-env/` and `examples/` never depend on it.

Each subdirectory is one investigation and stands alone: a `README.md` stating what was
reported, what was measured and what the cause turned out to be, alongside the scripts
that produce those measurements. Anything that changed as a *result* lands in the real
tree (and the investigation's README says what and where).

An investigation may reach outside this repo — into another user's suite, a foreign
software stack, a colleague's `cylc-run` — because that is where the problem lives.
Only ever read from those; snapshot the parts needed to reproduce.

| directory | what |
|---|---|
| [`dr932-mpi-scaling/`](dr932-mpi-scaling/) | u-dr932 reported 3–4× slower on Isambard 3 than Monsoon. Rank placement left to Slurm (108 ranks over 9–32 nodes) on top of an MPI with no Slingshot support. |
