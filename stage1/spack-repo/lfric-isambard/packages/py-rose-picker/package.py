# Copyright 2025
# SPDX-License-Identifier: (Apache-2.0 OR MIT)

# Extends mo-spack-packages' py-rose-picker with 2026.07.1, the rose_picker tag
# of the LFRic release the examples build. mo-spack-packages stops at 2026.03.2.
# Drop this override once it carries the version.
from spack_repo.metoffice.packages.py_rose_picker.package import (
    PyRosePicker as MetofficePyRosePicker,
)

from spack.package import *


class PyRosePicker(MetofficePyRosePicker):
    version("2026.07.1", sha256="7f0232ed94f5b9e343814462761484d171f8652f0f478b494dcb218d8ec53ef4")
