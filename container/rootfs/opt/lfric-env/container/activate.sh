# shellcheck shell=sh
# /opt/lfric-env/container/activate.sh — put the LFRic environment on, inside
# the container. SOURCE it (POSIX sh). Hooked into every way into the image:
#   login shells           /etc/profile.d/zz-lfric-env.sh   (Cylc jobs: bash -l)
#   apptainer exec/run/... /.singularity.d/env/90-lfric-env.sh
#   podman/docker run      /opt/lfric-env/container/bin/entrypoint
# so a bare `apptainer exec lfric-env.sif cylc ...` already has the environment,
# the same one `module load lfric-env/<version>/spack` gives on the host.
#
# Two cases:
#
#  * Re-entry from inside this container. The srun shim (bin/srun) starts each
#    MPI rank in a fresh container, and Apptainer resets PATH and
#    LD_LIBRARY_PATH on the way in. The shim saved the caller's values in
#    LFRIC_CONTAINER_PATH/LFRIC_CONTAINER_LD_LIBRARY_PATH; restore them, so a
#    rank sees exactly the task's environment. Everything else passed through.
#
#  * Anything else: a fresh activation. The caller's environment is the HOST's
#    (Apptainer passes it through), so first drop what only means something
#    there — Lmod state, the Cray PE, compiler flags, a host Python — then apply
#    the frozen module environment (env.sh, written by container/gen-env.sh).
#    A login shell always lands here: /etc/profile has just reset PATH.
#
# Must stay POSIX: Apptainer runs its env hooks in a built-in sh interpreter.

if [ -n "${LFRIC_CONTAINER_PATH:-}" ]; then
  PATH="$LFRIC_CONTAINER_PATH"
  LD_LIBRARY_PATH="${LFRIC_CONTAINER_LD_LIBRARY_PATH:-}"
  export PATH LD_LIBRARY_PATH
  unset LFRIC_CONTAINER_PATH LFRIC_CONTAINER_LD_LIBRARY_PATH
else
  # Host state that would misdirect the container's tools. Named lists, plus the
  # prefixes Lmod and the Cray PE use for their many variables.
  unset LD_LIBRARY_PATH LIBRARY_PATH CPATH C_INCLUDE_PATH CPLUS_INCLUDE_PATH \
        PKG_CONFIG_PATH MANPATH BASH_ENV ENV \
        MODULEPATH MODULESHOME LOADEDMODULES _LMFILES_ \
        CC CXX FC F77 F90 MPICC MPICXX MPIF90 LDMPI FPP \
        CFLAGS CXXFLAGS FFLAGS FCFLAGS CPPFLAGS LDFLAGS \
        PYTHONPATH PYTHONHOME VIRTUAL_ENV CONDA_PREFIX CONDA_DEFAULT_ENV CONDA_SHLVL \
        SPACK_ENV SPACK_ROOT
  for _lfric_v in $(env | sed -n 's/^\(LMOD[A-Za-z0-9_]*\|__LMOD[A-Za-z0-9_]*\|_ModuleTable[A-Za-z0-9_]*\|CRAY_[A-Za-z0-9_]*\|CRAYPE_[A-Za-z0-9_]*\|PE_[A-Za-z0-9_]*\)=.*/\1/p'); do
    unset "$_lfric_v"
  done
  unset _lfric_v
  PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
  export PATH
  . /opt/lfric-env/container/env.sh
  # The Slurm/MPI shims (sbatch, srun, ...) ahead of everything.
  PATH="/opt/lfric-env/container/bin:$PATH"
  # The container's Cylc site config: the module's, plus what makes a job
  # re-enter the container on the compute node (etc/cylc/flow/global.cylc).
  CYLC_SITE_CONF_PATH=/opt/lfric-env/container/etc/cylc
  # This repo's example scripts (scripts/common.sh) find the environment by
  # prefix and variant; inside the container that is the image's, whatever the
  # host's shell had.
  LFRIC_PREFIX=/opt/lfric-env
  LFRIC_STACK=spack
  LFRIC_CONTAINER=1
  export PATH CYLC_SITE_CONF_PATH LFRIC_PREFIX LFRIC_STACK LFRIC_CONTAINER
fi
