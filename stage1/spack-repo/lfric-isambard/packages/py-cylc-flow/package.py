# Copyright 2025
# SPDX-License-Identifier: (Apache-2.0 OR MIT)

# Extends the builtin py-cylc-flow with the newest 8.6 patch release. Upstream
# lfric_apps rose-stem needs cylc-flow >= 8.6 (CYLC_WORKFLOW_SRC_DIR); builtin
# stops at 8.6.4. 8.6.6 has the same requirements as 8.6.4, so the builtin's
# `when="@8.6:"` dependencies apply unchanged. Drop this override once builtin
# carries the version.
from spack_repo.builtin.packages.py_cylc_flow.package import PyCylcFlow as BuiltinPyCylcFlow

from spack.package import *


class PyCylcFlow(BuiltinPyCylcFlow):
    version("8.6.6", sha256="1ed390e5ea58d50c487fe79cfb84edadf9b1f950daf19a00bafd105e68356bcc")
