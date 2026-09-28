# Copyright 2025
# SPDX-License-Identifier: (Apache-2.0 OR MIT)

# Extends the builtin py-cylc-rose with 1.7.2, the release that pairs with
# cylc-flow 8.6. Builtin stops at 1.5.1, which requires cylc-flow 8.4. The
# requirements below are cylc-rose 1.7.2's own (PyPI requires_dist). Drop this
# override once builtin carries the version.
from spack_repo.builtin.packages.py_cylc_rose.package import PyCylcRose as BuiltinPyCylcRose

from spack.package import *


class PyCylcRose(BuiltinPyCylcRose):
    version("1.7.2", sha256="ec2ddcb410d65d233743e5646d0aa360bef7ff28aa89eac111a2f4365efccade")

    with when("@1.7"):
        depends_on("python@3.12:", type=("build", "run"))
        depends_on("py-metomi-rose@2.6:2.7", type=("build", "run"))
        depends_on("py-cylc-flow@8.6", type=("build", "run"))
        depends_on("py-ansimarkup", type=("build", "run"))
