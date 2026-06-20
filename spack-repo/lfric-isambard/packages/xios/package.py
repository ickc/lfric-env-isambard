# Copyright 2025
# SPDX-License-Identifier: (Apache-2.0 OR MIT)

import os

from spack_repo.builtin.build_systems.generic import Package
from spack_repo.builtin.packages.boost.package import Boost

from spack.package import *


class Xios(Package):
    """XML-IO-SERVER library for IO management of climate models."""

    homepage = "https://gitlab.in2p3.fr/ipsl/projets/xios-projects/xios"
    git = "https://gitlab.in2p3.fr/ipsl/projets/xios-projects/xios.git"

    # Former SVN revision 2252, pinned to the migrated Git history.
    version("2252", commit="26cc7d88e4f3fa1960461b377d9b8c82550a180e")

    variant(
        "mode",
        values=("debug", "dev", "prod"),
        default="dev",
        description="Build for debugging, development or production",
    )

    # XIOS revision 2252 assumes transitive STL headers that newer GCC/libstdc++
    # no longer expose consistently during the remap build.
    patch("gcc12_remap_standard_headers.patch", when="@2252")

    depends_on("c", type="build")
    depends_on("cxx", type="build")  # XIOS is heavily C++; Spack 1.x needs this declared
    depends_on("fortran", type="build")

    depends_on("netcdf-c+mpi")
    depends_on("netcdf-fortran")
    depends_on("hdf5+mpi")
    depends_on("mpi")
    depends_on(Boost.with_default_variants)
    depends_on("blitz")
    depends_on("perl", type="build")
    depends_on("perl-uri", type="build")
    depends_on("gmake", type="build")

    @when("%clang")
    def patch(self):
        self.patch_llvm()

    @when("%apple-clang")
    def patch(self):
        self.patch_llvm()

    def patch_llvm(self):
        """Fix type references that are ambiguous for clang."""
        for dirpath, dirnames, filenames in os.walk("src"):
            for filename in filenames:
                filepath = os.path.join(dirpath, filename)
                filter_file(r"([^:/])shared_ptr<", r"\1boost::shared_ptr<", filepath)
                filter_file(
                    r"oss.tellp\(\) *- *startPos", r"(long)oss.tellp() - startPos", filepath
                )

    def xios_env(self):
        file = join_path("arch", "arch-SPACK.env")
        touch(file)

    def xios_path(self):
        file = join_path("arch", "arch-SPACK.path")
        spec = self.spec
        paths = {
            "NETCDF_INC_DIR": spec["netcdf-c"].prefix.include,
            "NETCDF_LIB_DIR": spec["netcdf-c"].prefix.lib,
            "HDF5_INC_DIR": spec["hdf5"].prefix.include,
            "HDF5_LIB_DIR": spec["hdf5"].prefix.lib,
        }
        text = r"""
NETCDF_INCDIR="-I {NETCDF_INC_DIR}"
NETCDF_LIBDIR="-L {NETCDF_LIB_DIR}"
NETCDF_LIB="-lnetcdff -lnetcdf"

MPI_INCDIR=""
MPI_LIBDIR=""
MPI_LIB=""

HDF5_INCDIR="-I {HDF5_INC_DIR}"
HDF5_LIBDIR="-L {HDF5_LIB_DIR}"
HDF5_LIB="-lhdf5_hl -lhdf5"

OASIS_INCDIR=""
OASIS_LIBDIR=""
OASIS_LIB=""
"""
        with open(file, "w") as f:
            f.write(text.format(**paths))

    def xios_fcm(self):
        file = join_path("arch", "arch-SPACK.fcm")
        spec = self.spec
        param = dict()
        param["MPICXX"] = spec["mpi"].mpicxx
        param["MPIFC"] = spec["mpi"].mpifc
        param["CC"] = self.compiler.cc
        param["BOOST_INC_DIR"] = spec["boost"].prefix.include
        param["BOOST_LIB_DIR"] = spec["boost"].prefix.lib
        param["BLITZ_INC_DIR"] = spec["blitz"].prefix.include
        param["BLITZ_LIB_DIR"] = spec["blitz"].prefix.lib

        if spec.satisfies("%apple-clang"):
            libcxx = "-lc++"
        else:
            libcxx = "-lstdc++"

        if any(map(spec.satisfies, ("%gcc", "%intel", "%apple-clang", "%clang", "%fj"))):
            if spec.satisfies("%gcc"):
                base_fflags = "-D__NONE__ -ffree-line-length-none"
            else:
                base_fflags = "-D__NONE__"
            param["LIBCXX"] = libcxx
            param["BASE_FFLAGS"] = base_fflags
            text = r"""
%CCOMPILER      {MPICXX}
%FCOMPILER      {MPIFC}
%LINKER         {MPIFC}

%BASE_CFLAGS    -std=c++11 -w -D_GLIBCXX_USE_CXX11_ABI=0 \
                -I{BOOST_INC_DIR} -I{BLITZ_INC_DIR}
%PROD_CFLAGS    -O3 -DBOOST_DISABLE_ASSERTS
%DEV_CFLAGS     -g -O2
%DEBUG_CFLAGS   -g

%BASE_FFLAGS    {BASE_FFLAGS}
%PROD_FFLAGS    -O3
%DEV_FFLAGS     -g -O2
%DEBUG_FFLAGS   -g

%BASE_INC       -D__NONE__
%BASE_LD        -L{BOOST_LIB_DIR} -L{BLITZ_LIB_DIR} -lblitz {LIBCXX}

%CPP            {CC} -E
%FPP            {CC} -E -P -x c
%MAKE           make
""".format(
                **param
            )
        elif spec.satisfies("%cce"):
            if spec.satisfies("%cce@8.3.7:"):
                param.update({"CC_OPT_DEV": "-O2", "CC_OPT_PROD": "-O3"})
            else:
                param.update({"CC_OPT_DEV": "-O1", "CC_OPT_PROD": "-O1"})

            text = r"""
%CCOMPILER      {MPICXX}
%FCOMPILER      {MPIFC}
%LINKER         {MPIFC}

%BASE_CFLAGS    -DMPICH_SKIP_MPICXX -h msglevel_4 -h zero -h gnu \
                -I{BOOST_INC_DIR} -I{BLITZ_INC_DIR}
%PROD_CFLAGS    {CC_OPT_PROD} -DBOOST_DISABLE_ASSERTS
%DEV_CFLAGS     {CC_OPT_DEV}
%DEBUG_CFLAGS   -g

%BASE_FFLAGS    -em -m 4 -e0 -eZ
%PROD_FFLAGS    -O3
%DEV_FFLAGS     -G2
%DEBUG_FFLAGS   -g

%BASE_INC       -D__NONE__
%BASE_LD        -D__NONE__ -L{BOOST_LIB_DIR} -L{BLITZ_LIB_DIR} -lblitz

%CPP            cpp
%FPP            cpp -P -CC
%MAKE           gmake
""".format(
                **param
            )
        elif any(map(spec.satisfies, ("%nvhpc", "%pgi"))):
            text = r"""
%CCOMPILER      {MPICXX} -noswitcherror
%FCOMPILER      {MPIFC} -noswitcherror
%LINKER         {MPIFC} -noswitcherror

%BASE_CFLAGS    --c++11 -D__NONE__ -I{BOOST_INC_DIR} -I{BLITZ_INC_DIR}
%PROD_CFLAGS    -O3 -DBOOST_DISABLE_ASSERTS
%DEV_CFLAGS     -g -O2
%DEBUG_CFLAGS   -g

%BASE_FFLAGS    -D__NONE__
%PROD_FFLAGS    -O3
%DEV_FFLAGS     -g -O2
%DEBUG_FFLAGS   -g

%BASE_INC       -D__NONE__
%BASE_LD        -L{BOOST_LIB_DIR} -L{BLITZ_LIB_DIR} -lblitz -c++libs

%CPP            cpp
%FPP            cpp -P
%MAKE           gmake
""".format(
                **param
            )
        else:
            raise InstallError("Unsupported compiler.")

        with open(file, "w") as f:
            f.write(text)

    def install(self, spec, prefix):
        env["CC"] = spec["mpi"].mpicc
        env["CXX"] = spec["mpi"].mpicxx
        env["F77"] = spec["mpi"].mpif77
        env["FC"] = spec["mpi"].mpifc

        options = [
            "--full",
            "--%s" % spec.variants["mode"].value,
            "--arch",
            "SPACK",
            "--use_extern_boost",
            "--use_extern_blitz",
            "--netcdf_lib",
            "netcdf4_par",
            "--job",
            str(make_jobs),
        ]

        self.xios_env()
        self.xios_path()
        self.xios_fcm()

        make_xios = Executable("./make_xios")
        make_xios(*options)

        mkdirp(spec.prefix)
        install_tree("bin", spec.prefix.bin)
        install_tree("lib", spec.prefix.lib)
        install_tree("inc", spec.prefix.include)
        install_tree("etc", spec.prefix.etc)
        install_tree("cfg", spec.prefix.cfg)

    @run_after("install")
    @on_package_attributes(run_tests=True)
    def check_build(self):
        mpirun = os.getenv("MPIRUN")
        if mpirun is None:
            mpirun = "mpiexec"
        mpiexec = Executable(mpirun)
        with working_dir("inputs"):
            try:
                mpiexec("-n", "2", join_path("..", "bin", "test_client.exe"))
            except Exception:
                raise InstallError("Test failed; defining MPIRUN variable may help.")
