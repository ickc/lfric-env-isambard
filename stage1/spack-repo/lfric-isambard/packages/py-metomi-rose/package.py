# Copyright 2025
# SPDX-License-Identifier: (Apache-2.0 OR MIT)

# Extends the builtin py-metomi-rose with 2.7.1, which cylc-rose 1.7 requires
# (metomi-rose >=2.6,<2.8). Builtin stops at 2.4.2. 2.7.1's runtime requirements
# (aiofiles, jinja2, keyring, ldap3, metomi-isodatetime 3, psutil, requests) are
# the builtin's unconditional ones, so only the version and the Python floor are
# added. From 2.5.0 the sdist is named metomi_rose-*, which the builtin's pypi
# URL does not produce. Drop this override once builtin carries the version.
from spack_repo.builtin.packages.py_metomi_rose.package import (
    PyMetomiRose as BuiltinPyMetomiRose,
)

from spack.package import *


class PyMetomiRose(BuiltinPyMetomiRose):
    version("2.7.1", sha256="e20376588f1048ee715ffebe0dc8834e70dccd6d398794dff13586d764f70025")

    depends_on("python@3.12:", when="@2.7:", type=("build", "run"))

    def url_for_version(self, version):
        name = "metomi_rose" if version >= Version("2.5") else "metomi-rose"
        return f"https://files.pythonhosted.org/packages/source/m/metomi-rose/{name}-{version}.tar.gz"
