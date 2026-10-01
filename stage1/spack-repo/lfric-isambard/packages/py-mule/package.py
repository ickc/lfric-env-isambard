# Copyright 2025
# SPDX-License-Identifier: (Apache-2.0 OR MIT)

from spack_repo.builtin.build_systems.python import PythonPackage

from spack.package import *


class PyMule(PythonPackage):
    """Mule: read and write the files of the Met Office Unified Model (fieldsfiles,
    dumps, ancillaries, LBCs, PP).

    Packaged nowhere else (not PyPI, conda-forge or Spack). lfric_apps' rose-stem
    generate_weights task and lfricinputs' lbc2ff use it. One of three packages
    built from subdirectories of the MetOffice/mule repository, with
    py-um-packing and py-um-utils.
    """

    homepage = "https://github.com/MetOffice/mule"
    url = "https://github.com/MetOffice/mule/archive/refs/tags/2026.09.1.tar.gz"

    license("BSD-3-Clause")

    version("2026.09.1", sha256="fae8c2670a8641cb39c44e6ee360323a867c91ca0d8810558b468d5ad7789267")

    build_directory = "mule"

    depends_on("py-setuptools@42:", type="build")
    with default_args(type=("build", "run")):
        depends_on("py-numpy")
        depends_on("py-six")
    # mule unpacks WGDOS-packed fields with um_packing when it is importable.
    depends_on("py-um-packing@2026.09.1", type="run", when="@2026.09.1")
