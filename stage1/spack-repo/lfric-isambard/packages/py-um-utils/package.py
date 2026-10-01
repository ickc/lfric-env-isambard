# Copyright 2025
# SPDX-License-Identifier: (Apache-2.0 OR MIT)

from spack_repo.builtin.build_systems.python import PythonPackage

from spack.package import *


class PyUmUtils(PythonPackage):
    """um_utils: the mule command-line utilities (mule-pumf, mule-cumf,
    mule-cutout, ...) and their library, um_utils. Built from the um_utils
    subdirectory of MetOffice/mule; see py-mule.
    """

    homepage = "https://github.com/MetOffice/mule"
    url = "https://github.com/MetOffice/mule/archive/refs/tags/2026.09.1.tar.gz"

    license("BSD-3-Clause")

    version("2026.09.1", sha256="fae8c2670a8641cb39c44e6ee360323a867c91ca0d8810558b468d5ad7789267")

    build_directory = "um_utils"

    depends_on("py-setuptools@42:", type="build")
    with default_args(type=("build", "run")):
        depends_on("py-numpy")
        depends_on("py-six")
        depends_on("py-mule@2026.09.1", when="@2026.09.1")
