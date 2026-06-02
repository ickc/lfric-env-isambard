#!/usr/bin/env bash
# Fix gdbm 1.26 build failure: the source archive has mismatched timestamps
# so *.am files appear newer than the corresponding *.in files. When make
# runs in tests/ it tries to regenerate tests/Makefile.in via automake-1.16,
# which is not available → "automake-1.16: command not found".
#
# Adding automake as a build dep causes perl→gdbm→automake→perl cycle.
# The clean fix is a @run_before("configure") hook that touches all *.in
# files (and configure/aclocal.m4) so they appear newer than any *.am file.
set -o pipefail
_here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="${PIXI_PROJECT_ROOT:-$(cd "$_here/.." && pwd)}"
GDBM_PKG="$REPO_ROOT/vendor/spack-packages/repos/spack_repo/builtin/packages/gdbm/package.py"

if [ ! -f "$GDBM_PKG" ]; then
  echo "INFO: gdbm package.py not found; skipping"
  exit 0
fi

# Idempotent: skip if the touch hook is already present
if grep -q '_touch_generated_files' "$GDBM_PKG"; then
  echo "INFO: gdbm timestamp-touch patch already applied"
  exit 0
fi

# Remove any previous (incorrect) automake/autoconf dep lines if present
sed -i '/^    depends_on("automake", type="build")$/d' "$GDBM_PKG"
sed -i '/^    depends_on("autoconf", type="build")$/d' "$GDBM_PKG"

# Inject the touch hook before configure_args using Python (path via env var)
GDBM_PKG="$GDBM_PKG" python3 - <<'PYEOF'
import os, sys

path = os.environ["GDBM_PKG"]
with open(path) as fh:
    src = fh.read()

hook = '''\
    @run_before("configure")
    def _touch_generated_files(self):
        """gdbm-1.26 ships with mismatched *.am / *.in timestamps; make tries
        to invoke automake-1.16 which is absent.  Touch generated files so
        make does not attempt to regenerate them."""
        import os as _os
        for root, _, files in _os.walk("."):
            for f in files:
                if f.endswith(".in") or f in ("aclocal.m4", "configure"):
                    _os.utime(_os.path.join(root, f), None)

'''

if 'def configure_args' in src:
    src = src.replace('    def configure_args', hook + '    def configure_args', 1)
else:
    src = src.rstrip('\n') + '\n' + hook + '\n'

with open(path, 'w') as fh:
    fh.write(src)

print("INFO: gdbm timestamp-touch hook injected")
PYEOF
