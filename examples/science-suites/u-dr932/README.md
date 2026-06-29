u-dr932
=======

This is a standalone LFRic suite for Shallow and Deep Hot Jupiter Temperature Forcing Cases.

Since Apps vn3.0 the workflow has been setup to run using git sources. Please
see below for instructions on modifying suites to run with git sources. All
revisions of the LFRic trunks that were available on MOSRS are also available
from git and so this setup of suite can be used for older LFRic versions. Any
MOSRS branches will need porting to git before being used.

See also:
- `../README.md`
- `../../README.md`
- `../../env_lfric_gcc/README.md`
- `../../env_lfric_nvhpc/README.md`

Setting Source Codes
--------------------

Different sources for the required source codes can be set in the
`dependencies.yaml` file. LFRic Apps requires sources to be set for Casim,
Jules, LFRic Apps, LFRic Core, Socrates and UKCA. But other git sources can be
added if data from them is required, eg. the socrates-spectral repository.

Multiple branches can be combined and merged if desired (similar to the
fcm_extract functionality for working with subversion repositories). To do this,
set multiple sources in the `dependencies.yaml` file:

```yaml
lfric_apps:
    - source: git@github.com:MetOffice/lfric_apps.git
      ref: 2025.12.1
    - source: git@github.com:my_fork/lfric_apps.git
      ref: my_branch
```

This will first clone the MetOffice Apps repository and checkout the `2025.12.1`
tag. It will then merge in my_branch from my_fork. It is up to the user to
ensure the branches are mergeable - an error will be raised if conflicts occur (
although conflicts in the rose-stem directory and repository dependencies.yaml
file will be ignored).

> **Note — merging is not yet supported in this repo.** The offline extractor used
> here (`site/extract-sources.sh`) reads each repo's **first** `source`/`ref` entry
> only and materialises it via `git archive` from the vendored mirror; it does not
> merge a fork branch onto a tag. Declare a single ref per repo, already staged in
> the mirror. (Fork-on-tag merge support is tracked as `PLAN.md` follow-up 2.)

Changing a workflow from fcm to git sources
-------------------------------------------

To change a workflow to work with git sources will involve some manual changes.

* Take a copy of the `app/extract` directory from here — it runs this repo's
  offline `site/extract-sources.sh` (`git archive` from the vendored local
  mirrors), not the upstream `get_git_sources.py`/`merge_sources.py` clone step.
  You may also need to update the tweak_iodef source.
* In the `flow.cylc`:
  * add the new `extract` task. See the `graph` section and the `[[extract]]`
    sections.
  * Add `PHYSICS_ROOT = $SOURCE_ROOT` to the environment variable list.
  * Add `install = dependencies.yaml` to the `scheduler` section.
* Create a `dependencies.yaml` file - see above.

Source extraction here is fully offline: `extract-sources.sh` reads each declared
`repo@ref` from this repo's vendored local mirrors (`vendor/lfric_apps`,
`lfric_core`, `physics/*`) via `git archive` — no github clone, no mirror/token
auth. A ref must be staged into the mirror before a suite can build it; a ref
absent from the mirror is a hard error naming what to stage.
