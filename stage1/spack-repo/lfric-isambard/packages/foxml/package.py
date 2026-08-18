# Copyright 2013-2022 Lawrence Livermore National Security, LLC and other
# Spack Project Developers. See the top-level COPYRIGHT file for details.
#
# SPDX-License-Identifier: (Apache-2.0 OR MIT)

# Ported into the local "lfric" repo from MetOffice/simit-spack when the build
# moved to mo-spack-packages. mo-spack-packages does not carry FoX, and the
# Spack builtin "fox" package is the unrelated FOX-toolkit C++ GUI library
# (fox-toolkit.org), not the andreww/fox Fortran/XML library LFRic needs.

from spack.package import *


class Foxml(CMakePackage):
    """FoX - the Fortan/XML library.

    FoX is an XML library written in Fortran 95. It allows software
    developers to read, write and modify XML documents from Fortran
    applications without the complications of dealing with
    multi-language development. FoX can be freely redistributed as
    part of open source and commercial software packages.
    """

    homepage = "https://github.com/andreww/fox"
    git = "https://github.com/andreww/fox.git"

    version(
        "6f60cf1",
        commit="6f60cf178d0776b21406303e91f1e6b42ff0f204",
        preferred=True,
    )

    # FoX is Fortran 95 (its CMake build also enables C); Spack 1.x requires the
    # language build deps to be declared so the compiler wrappers get configured.
    depends_on("c", type="build")
    depends_on("fortran", type="build")
