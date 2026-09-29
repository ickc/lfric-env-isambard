# Copyright 2025
# SPDX-License-Identifier: (Apache-2.0 OR MIT)

# Extends the builtin py-cylc-uiserver (what `cylc gui` needs) with 1.9.4, the
# newest release for cylc-flow 8.6. Builtin stops at 1.9.1; 1.9.4 has the same
# requirements, but the builtin gates them on `when="@1.9.1"`, so they are
# restated for 1.9.4 here. Drop this override once builtin carries the version.
from spack_repo.builtin.packages.py_cylc_uiserver.package import (
    PyCylcUiserver as BuiltinPyCylcUiserver,
)

from spack.package import *


class PyCylcUiserver(BuiltinPyCylcUiserver):
    version("1.9.4", sha256="9ce306b2bb0de0e3ff7dceaa337405e7df2eabd678f88b7eb510f4a67dd8adc2")

    with when("@1.9.4"):
        depends_on("py-cylc-flow@8.6.4:8.6", type=("build", "run"))
        depends_on("py-cherrypy", type=("build", "run"))
