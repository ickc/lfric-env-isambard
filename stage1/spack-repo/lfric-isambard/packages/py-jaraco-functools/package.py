# Copyright 2025
# SPDX-License-Identifier: (Apache-2.0 OR MIT)

# Extends the builtin py-jaraco-functools, which has only 2.0, with 4.6.0.
# py-cylc-uiserver -> py-cherrypy -> py-portend -> py-tempora pulls it in, and
# builtin py-setuptools conflicts with jaraco-functools@:3 from 75.3.4 on, so
# with only 2.0 available `cylc gui` makes the environment unsolvable. 4.x ships
# a pyproject.toml build and an underscored sdist name. Drop this override once
# builtin carries a 4.x version.
from spack_repo.builtin.packages.py_jaraco_functools.package import (
    PyJaracoFunctools as BuiltinPyJaracoFunctools,
)

from spack.package import *


class PyJaracoFunctools(BuiltinPyJaracoFunctools):
    version("4.6.0", sha256="880c577ec9720b3a052d5bc611fb9f2269b3d87902ef42440df443b88e443280")

    with when("@4:"):
        depends_on("python@3.10:", type=("build", "run"))
        depends_on("py-setuptools@61.2:", type="build")
        depends_on("py-setuptools-scm@3.4.1:+toml", type="build")

    def url_for_version(self, version):
        if version >= Version("4"):
            name = "jaraco_functools"
        else:
            name = "jaraco.functools"
        return f"https://files.pythonhosted.org/packages/source/j/jaraco.functools/{name}-{version}.tar.gz"
