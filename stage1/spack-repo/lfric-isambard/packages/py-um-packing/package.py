# Copyright 2025
# SPDX-License-Identifier: (Apache-2.0 OR MIT)

from spack_repo.builtin.build_systems.python import PythonPackage

from spack.package import *


class PyUmPacking(PythonPackage):
    """um_packing: the SHUMlib WGDOS packing library as a Python extension, which
    mule uses to read and write packed UM fields. Built from the um_packing
    subdirectory of MetOffice/mule; see py-mule.
    """

    homepage = "https://github.com/MetOffice/mule"
    url = "https://github.com/MetOffice/mule/archive/refs/tags/2026.09.1.tar.gz"

    license("BSD-3-Clause")

    version("2026.09.1", sha256="fae8c2670a8641cb39c44e6ee360323a867c91ca0d8810558b468d5ad7789267")

    build_directory = "um_packing"

    depends_on("c", type="build")
    depends_on("py-setuptools@42:", type="build")
    depends_on("py-numpy", type=("build", "link", "run"))
    depends_on("py-six", type=("build", "run"))
    depends_on("shumlib")

    def patch(self):
        # um_packing is written against SHUMlib's own Makefile build, which makes
        # one library per component (shum_byteswap, shum_wgdos_packing, ...), each
        # with a generated c_shum_<component>_version.h declaring
        # get_shum_<component>_version(). Spack builds shumlib with CMake, which
        # installs a single libshum exporting one GET_SHUMLIB_VERSION() and no
        # per-component version headers.
        # (filter_file works line by line, so each name becomes "shum"; the linker
        # takes the repeats.)
        filter_file(
            r'"shum_(byteswap|wgdos_packing|string_conv|constants)"',
            '"shum"',
            join_path("um_packing", "setup.py"),
        )
        src = join_path("um_packing", "lib", "um_packing", "um_packing.c")
        filter_file(
            r'#include "c_shum_wgdos_packing_version.h"',
            "#include <inttypes.h>\nextern int64_t GET_SHUMLIB_VERSION(void);",
            src,
        )
        filter_file(r"get_shum_wgdos_packing_version\(\)", "GET_SHUMLIB_VERSION()", src)

    def setup_build_environment(self, env):
        # shumlib installs libshum to lib64, which the compiler wrapper does not
        # add, and its recipe declares no libs for Spack to find it by.
        libdir = find_libraries("libshum", self.spec["shumlib"].prefix, recursive=True).directories[0]
        env.prepend_path("LIBRARY_PATH", libdir)
        env.append_flags("LDFLAGS", "-Wl,-rpath," + libdir)
