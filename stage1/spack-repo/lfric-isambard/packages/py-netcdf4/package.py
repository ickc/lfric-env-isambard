# Copyright 2025
# SPDX-License-Identifier: (Apache-2.0 OR MIT)

# Extends the builtin py-netcdf4 with the build fixes it needs here.
#
# 1. A direct dependency on MPI for +mpi. The builtin reaches MPI only through
#    hdf5/netcdf-c, but on the cray variant those are externals, which carry no
#    dependencies of their own, so the compiler wrapper never adds cray-mpich's
#    include dir and the Cray HDF5 headers fail on `#include <mpi.h>`.
# 2. -O2. Spack's python (~optimizations) hands setuptools no optimisation flag,
#    so extensions compile at -O0, and netCDF4's bundled nc_complex declares
#    pfnc_inq_vardimid & co. as C99 `inline` with no external definition: at -O0
#    they are not inlined and the module fails to import with "undefined symbol:
#    pfnc_inq_vardimid". (Every wheel and conda build compiles at -O2 or above.)
# 3. No nc-config for an external netCDF (cray variant). The builtin sets
#    USE_NCCONFIG=1, but Cray's nc-config reports no libraries at all (Cray's
#    compiler wrappers add -lnetcdf themselves), so the module links without
#    libnetcdf and fails to import with "undefined symbol: nc_rc_set". setup.py
#    has no switch to refuse a working nc-config (USE_NCCONFIG=0 means "unset",
#    and it then uses nc-config anyway), so patch its detection off; it then links
#    netcdf/hdf5 from the NETCDF4_DIR/HDF5_DIR the builtin already sets.
#
# Drop this once the builtin covers them.
from spack_repo.builtin.packages.py_netcdf4.package import PyNetcdf4 as BuiltinPyNetcdf4

from spack.package import *


class PyNetcdf4(BuiltinPyNetcdf4):
    depends_on("mpi", when="+mpi")

    def patch(self):
        if self.spec["netcdf-c"].external:
            filter_file(
                r"HAS_NCCONFIG = subprocess\.call\(\[ncconfig, '--libs'\]\) == 0",
                "HAS_NCCONFIG = False",
                "setup.py",
            )

    def flag_handler(self, name, flags):
        flags, env_flags, build_flags = super().flag_handler(name, flags)
        if name == "cflags":
            flags.append("-O2")
        return flags, env_flags, build_flags
