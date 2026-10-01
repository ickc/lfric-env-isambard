# Copyright 2025
# SPDX-License-Identifier: (Apache-2.0 OR MIT)

from spack_repo.builtin.build_systems.python import PythonPackage

from spack.package import *


class PyScitoolsIris(PythonPackage):
    """Iris: analysis and visualisation of Earth science data (CF, netCDF, UM).

    Not in the Spack builtin repository. lfric_apps' rose-stem plot and
    output-metadata tasks import it.
    """

    homepage = "https://scitools-iris.readthedocs.io"
    pypi = "scitools-iris/scitools_iris-3.16.1.tar.gz"
    git = "https://github.com/SciTools/iris.git"

    license("BSD-3-Clause")

    version("3.16.1", sha256="0496c46675415a160d72b2ba33e51968fc2a58d847929cbba54ccec71e0486ef")

    depends_on("python@3.12:", type=("build", "run"))
    with default_args(type="build"):
        depends_on("py-setuptools@77.0.3:")
        depends_on("py-setuptools-scm@8:")
    # requirements/pypi-core.txt of the release.
    with default_args(type=("build", "run")):
        depends_on("py-cartopy@0.21:")
        depends_on("py-cf-units@3.1:")
        depends_on("py-cftime@1.5:")
        depends_on("py-dask@2025.1.0:2025.9,2025.11:+array")
        depends_on("py-matplotlib@3.5:")
        depends_on("py-netcdf4")
        depends_on("py-numpy@1.24:1.24.2,1.24.4:")
        depends_on("py-pyproj")
        depends_on("py-scipy")
        depends_on("py-shapely@:1.8.2,1.8.4:")
        depends_on("py-xxhash")
