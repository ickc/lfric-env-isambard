# Copyright 2025
# SPDX-License-Identifier: (Apache-2.0 OR MIT)

import os

from spack.package import *


class LfricRoseMeta(Package):
    """The Rose metadata (rose-meta) of the LFRic release this environment builds.

    `rose app-upgrade`, `rose macro` and `rose edit` on an LFRic suite's app configs
    need the metadata of lfric_apps, lfric_core and JULES on ROSE_META_PATH. Only the
    rose-meta directories are installed, laid out as <prefix>/share/rose-meta/<repo>/
    <path in repo>/rose-meta, so the module can export them without the user having to
    initialise this repo's source submodules. Casim, SOCRATES and UKCA carry no
    rose-meta of their own (theirs lives in lfric_apps).
    """

    homepage = "https://github.com/MetOffice/lfric_apps"

    # The same commits the repo's vendor/ submodules pin, which are the sources the
    # examples build: lfric_apps 2026.07.1, lfric_core 2026.07.2, jules 2026.07.1.
    # The version names the lfric_apps release, which is what a suite's meta= lines
    # (vn3.2) follow.
    version(
        "2026.07.1",
        sha256="afa439f2aa32f401cb8ac014b297ad3a0cf9d0b41847933cb33bceb43a9e195e",
        url="https://github.com/MetOffice/lfric_apps/archive/bd921320379fb6ef32eb9642acf8496dfb9dd1da.tar.gz",
    )

    resource(
        name="lfric_core",
        url="https://github.com/MetOffice/lfric_core/archive/c3fd2d4256d3c856fd08b43b43d2667e534f5e2c.tar.gz",
        sha256="be2593eb7b3c6f5c7238e4ee6a36a0d5081f97cd8854e8e07db319e5a818e081",
        destination="resources",
        placement="lfric_core",
        when="@2026.07.1",
    )
    resource(
        name="jules",
        url="https://github.com/MetOffice/jules/archive/b698279da9ba0d11405e0531613290b42ce15bdd.tar.gz",
        sha256="b71ae8f49c92488d01f7469a2f87ae5e31b0d244c79bdfa86f511b5d4b27b26f",
        destination="resources",
        placement="jules",
        when="@2026.07.1",
    )

    def install(self, spec, prefix):
        trees = {
            "lfric_apps": ".",
            "lfric_core": join_path("resources", "lfric_core"),
            "jules": join_path("resources", "jules"),
        }
        dest_root = join_path(prefix, "share", "rose-meta")
        for repo, src in trees.items():
            for dirpath, dirnames, _ in os.walk(src):
                # Skip the unpacked resources when walking lfric_apps itself.
                if repo == "lfric_apps" and dirpath == ".":
                    dirnames[:] = [d for d in dirnames if d != "resources"]
                if os.path.basename(dirpath) == "rose-meta":
                    rel = os.path.relpath(dirpath, src)
                    install_tree(dirpath, join_path(dest_root, repo, rel))
                    dirnames[:] = []
