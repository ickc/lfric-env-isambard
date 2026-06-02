#!/usr/bin/env bash
# Auto-generated from install.sh. Repo-wide Spack 1.0 API/import normalisation for simit-spack.
set -o pipefail
_here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="${PIXI_PROJECT_ROOT:-$(cd "$_here/.." && pwd)}"
# Bundles 4 install.sh passes; must run after the per-package patches.
SIMIT_SPACK_DIR="$REPO_ROOT/vendor/simit-spack"
SPACK_DIR="$REPO_ROOT/vendor/spack"
SIMIT_REPO="$SIMIT_SPACK_DIR/repos/metoffice"
info() { echo "INFO: $*"; }
warn() { echo "WARN: $*" >&2; }
fail() { echo "ERROR: $*" >&2; return 1; }

ensure_repo_api_v1() {
  local repo_yaml="$1"
  if [ ! -f "$repo_yaml" ]; then
    return 0
  fi
  if grep -q "^[[:space:]]*api:" "$repo_yaml"; then
    return 0
  fi
  local tmp_file
  tmp_file="$(mktemp)"
  awk '{
    print $0
    if ($0 ~ /^[[:space:]]*repo:[[:space:]]*$/) {
      print "  api: v1.0"
    }
  }' "$repo_yaml" > "$tmp_file"
  mv "$tmp_file" "$repo_yaml"
}

fix_spack_pkg_builtin_imports() {
  local repo_dir="$1"
  local files=()
  if command -v rg >/dev/null 2>&1; then
    mapfile -t files < <(rg -l "spack\\.pkg\\.builtin" "$repo_dir")
  else
    mapfile -t files < <(grep -rl "spack.pkg.builtin" "$repo_dir")
  fi
  for pkg_file in "${files[@]}"; do
    local names=()
    if command -v rg >/dev/null 2>&1; then
      mapfile -t names < <(rg -o "spack\\.pkg\\.builtin\\.[A-Za-z0-9_-]+" "$pkg_file" | sed "s/.*builtin\\.//")
    else
      mapfile -t names < <(grep -o "spack.pkg.builtin.[A-Za-z0-9_-]*" "$pkg_file" | sed "s/.*builtin\\.//")
    fi
    for pkg_name in "${names[@]}"; do
      local pkg_mod="${pkg_name//-/_}"
      sed -i "s|spack.pkg.builtin.${pkg_name}|spack_repo.builtin.packages.${pkg_mod}.package|g" "$pkg_file"
    done
  done
}

fix_build_system_imports() {
  local repo_dir="$1"
  local matches=()
  local has_build_systems=0
  if [ -d "$SPACK_DIR/lib/spack/spack/build_systems" ]; then
    has_build_systems=1
  fi
  local bs_entries=(
    "PythonPackage:python"
    "PerlPackage:perl"
    "CMakePackage:cmake"
    "AutotoolsPackage:autotools"
    "MakefilePackage:makefile"
  )
  if command -v rg >/dev/null 2>&1; then
    mapfile -t matches < <(rg -l "Package|spack\\.build_systems" "$repo_dir")
  else
    mapfile -t matches < <(grep -rl -e "Package" -e "spack.build_systems" "$repo_dir")
  fi
  for pkg in "${matches[@]}"; do
    for entry in "${bs_entries[@]}"; do
      local klass="${entry%%:*}"
      local module="${entry##*:}"
      if [ "$has_build_systems" -eq 1 ]; then
        if grep -q "from spack.package import ${klass}" "$pkg"; then
          sed -i "s|from spack.package import ${klass}|from spack.package import *\\nfrom spack.build_systems.${module} import ${klass}|" "$pkg"
        fi
        if grep -q "from spack.build_systems.${module} import ${klass}" "$pkg"; then
          if ! grep -q "from spack.package import \\*" "$pkg"; then
            sed -i "0,/from spack.build_systems.${module} import ${klass}/s//from spack.package import *\\nfrom spack.build_systems.${module} import ${klass}/" "$pkg"
          fi
        fi
      else
        sed -i "/from spack.build_systems.${module} import ${klass}/d" "$pkg"
        if grep -q "from spack.package import ${klass}" "$pkg"; then
          sed -i "s|from spack.package import ${klass}|from spack.package import *|" "$pkg"
        fi
      fi
    done
  done
}

ensure_spack_package_imports() {
  local repo_dir="$1"
  local files=()
  if command -v rg >/dev/null 2>&1; then
    mapfile -t files < <(rg --files -g "package.py" "$repo_dir")
  else
    mapfile -t files < <(find "$repo_dir" -name package.py)
  fi
  for pkg_file in "${files[@]}"; do
    if grep -q "from spack.package import \\*" "$pkg_file"; then
      continue
    fi
    if ! grep -Eq "(^|[^A-Za-z_])(version|depends_on|variant|extends|conflicts|resource|patch|provides|maintainers)\\s*\\(" "$pkg_file"; then
      continue
    fi
    if head -n 1 "$pkg_file" | grep -q "^#!"; then
      {
        read -r first_line
        echo "$first_line"
        echo "from spack.package import *"
        cat
      } < "$pkg_file" > "${pkg_file}.tmp" && mv "${pkg_file}.tmp" "$pkg_file"
    else
      {
        echo "from spack.package import *"
        cat "$pkg_file"
      } > "${pkg_file}.tmp" && mv "${pkg_file}.tmp" "$pkg_file"
    fi
  done
}

ensure_repo_api_v1 "$SIMIT_REPO/repo.yaml"
fix_spack_pkg_builtin_imports "$SIMIT_REPO"
fix_build_system_imports "$SIMIT_REPO"
ensure_spack_package_imports "$SIMIT_REPO"
