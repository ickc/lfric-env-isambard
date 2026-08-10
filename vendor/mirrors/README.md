# `vendor/mirrors/` — the vendored submodules in Met Office git-mirror layout

Symlinks only. `MetOffice/<repo>.git` → the matching submodule under `vendor/`.

The Met Office extract (`merge_sources.py --mirrors --mirror_loc=<dir>`, from
SimSys_Scripts) resolves a dependency `git@github.com:MetOffice/lfric_apps.git`
to `<dir>/MetOffice/lfric_apps.git`, clones that, and fetches the declared ref
from it. That mirror host does not exist on Isambard 3 — this directory is the
same layout over the clones this repo already vendors, so the *upstream* extract
mechanism works here unchanged, and offline.

A science suite selects it with `USE_MIRRORS=true` (see
`examples/science-suites/u-dr932/rose-suite.conf`). The default is
`USE_TOKENS=true`, which clones from github over https — the six LFRic
repositories are public, so no token is actually needed.

Checked with the network denied, which is the only way to check it:

```bash
GIT_TERMINAL_PROMPT=0 GIT_SSH_COMMAND=false \
  python3 merge_sources.py -d <suite> -p <dest> --mirrors --mirror_loc=$PWD/vendor/mirrors
```

**Offline contract for this path.** A ref is clonable from here only if it is
already in the submodule (they are full clones, carrying every fetched tag and
branch). To build a fork or a new branch through the mirror path, fetch it into
the submodule once:

```bash
git -C vendor/lfric_apps remote add <fork> <url>
git -C vendor/lfric_apps fetch <fork>
```

after which it is offline. Or just leave `USE_TOKENS=true` and let the extract
clone the fork from github, which is what a Met Office user would do anyway.
