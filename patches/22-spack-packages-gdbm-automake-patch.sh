#!/usr/bin/env bash
# Fix gdbm 1.26 build failure: the source archive ships with mismatched autotools
# timestamps, so the generated files (configure, aclocal.m4, */Makefile.in) can
# look OLDER than the inputs they are generated from (configure.ac, */Makefile.am).
# make then tries to regenerate them and fails, because the environment has
# neither the autoconf nor the automake version the tree was generated with:
#   > configure.ac:25: error: Autoconf version 2.71 or higher is required
#   > automake-1.16: command not found
#
# Adding automake/autoconf as build deps causes a perl->gdbm->automake->perl
# cycle, so the fix is a @run_before("configure") hook that rewrites the mtimes.
#
# It must impose the autotools dependency ORDER, not just "touch everything to
# now": aclocal.m4 is generated from configure.ac, and configure + *.in are
# generated from configure.ac + aclocal.m4. An earlier version of this patch
# set every generated file to the current time in os.walk() order, which left
# the relative order of aclocal.m4 vs configure down to readdir() ordering —
# it happened to work for a while, then a rebuild put aclocal.m4 last and make
# duly re-ran autoconf. Stamping explicit, increasing mtimes is deterministic.
set -o pipefail
_here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="${PIXI_PROJECT_ROOT:-$(cd "$_here/.." && pwd)}"
GDBM_PKG="$REPO_ROOT/vendor/spack-packages/repos/spack_repo/builtin/packages/gdbm/package.py"

if [ ! -f "$GDBM_PKG" ]; then
  echo "INFO: gdbm package.py not found; skipping"
  exit 0
fi

# Idempotent: skip only if the CURRENT (ordered) hook is present. The marker is
# the ordered helper, so a tree still carrying the old racy hook gets rewritten.
if grep -q '_stamp_autotools_order' "$GDBM_PKG"; then
  echo "INFO: gdbm timestamp-order patch already applied"
  exit 0
fi

# Remove any previous (incorrect) automake/autoconf dep lines if present
sed -i '/^    depends_on("automake", type="build")$/d' "$GDBM_PKG"
sed -i '/^    depends_on("autoconf", type="build")$/d' "$GDBM_PKG"

# Inject the touch hook before configure_args using Python (path via env var)
GDBM_PKG="$GDBM_PKG" python3 - <<'PYEOF'
import os
import re

path = os.environ["GDBM_PKG"]
with open(path) as fh:
    src = fh.read()

# Drop the previous, racy hook (touched everything to "now" in os.walk order).
src = re.sub(
    r'\n    @run_before\("configure"\)\n'
    r'    def _touch_generated_files\(self\):.*?(?=\n    def |\n\nclass |\Z)',
    "\n",
    src,
    flags=re.S,
)

hook = '''\
    @run_before("configure")
    def _stamp_autotools_order(self):
        """gdbm ships mismatched autotools timestamps, so make tries to re-run
        autoconf/automake, which are deliberately not build deps (they would
        create a perl->gdbm->automake->perl cycle).

        Stamp explicit, increasing mtimes in autotools dependency order so
        every generated file is strictly newer than its inputs:

            configure.ac / *.am / m4 inputs   base
            aclocal.m4                        base + 10
            configure / *.in                  base + 20

        Touching them all to "now" instead is NOT enough: it leaves the order
        of aclocal.m4 vs configure to readdir(), and make re-runs autoconf
        whenever aclocal.m4 lands last.
        """
        import os as _os

        src_root = self.stage.source_path
        base = _os.path.getmtime(src_root) - 100.0
        inputs, generated = [], {}
        for root, _, files in _os.walk(src_root):
            for f in files:
                p = _os.path.join(root, f)
                if f == "aclocal.m4":
                    generated[p] = base + 10.0
                elif f == "configure" or f.endswith(".in"):
                    generated[p] = base + 20.0
                elif f.endswith((".ac", ".am", ".m4")):
                    inputs.append(p)
        for p in inputs:
            _os.utime(p, (base, base))
        for p, when in generated.items():
            _os.utime(p, (when, when))

'''

if 'def configure_args' in src:
    src = src.replace('    def configure_args', hook + '    def configure_args', 1)
else:
    src = src.rstrip('\n') + '\n\n' + hook

with open(path, 'w') as fh:
    fh.write(src)

print("INFO: gdbm autotools timestamp-order hook injected")
PYEOF
