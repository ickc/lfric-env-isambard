-- scripts/lfric-env.lua — LFRic Apps environment modulefile logic (Lmod / Lua).
--
-- This is the AUDITABLE half of activation. The generated per-variant modulefile
-- ($PREFIX/modulefiles/lfric-env/<variant>.lua, written by gen-modulefile.sh)
-- only defines a flat table of per-build paths, then runs THIS file with it:
--     assert(loadfile(".../scripts/lfric-env.lua"))(data)
-- So everything below is static and version-controlled; only the path data
-- changes per build. (Lmod's sandbox forbids dofile() and reading undeclared
-- globals, so we pass the data as an argument and read it via `...`.)
--
-- Self-contained (setenv / prepend_path / pushenv) — with ONE exception this
-- file itself cannot express: the cray variant needs `load()`/`try_load()` for
-- PrgEnv-gnu + the Cray HDF5/netCDF modules, so that `module load
-- lfric-env/<version>/cray` alone is enough to compile and run against this
-- environment (a caller shouldn't need to know which Cray PE modules or
-- FC/CXX/LDMPI exports back a given build — that used to be duplicated in
-- examples/minimal-compile/build.sh and would otherwise leak into every
-- science-suite task too). Lmod resolves module hierarchy (MODULEPATH
-- changes from loading a compiler family) by statically scanning the
-- TOP-LEVEL modulefile source for `load(...)` calls — a `load()` reached only
-- via this file's `loadfile()` is invisible to that scan and silently does
-- nothing (verified: `try_load()` still works when nested, but the required
-- `load()` calls do not). So those Cray module loads are emitted directly
-- into the generated per-build modulefile by gen-modulefile.sh, BEFORE it
-- calls into this file — this file only consumes their effect (FC/CXX/LDMPI,
-- built assuming ftn/CC/cray-mpich are already on PATH by the time it runs).
-- The spack variant needs no nested loads: its MPI/HDF5/netCDF are
-- from-source in the view, so FC/CXX point at the view's own mpif90/mpic++
-- wrappers and its libs reach LD_LIBRARY_PATH via d.cray_libs (empty for
-- spack) and the view -L/-rpath added below.

local d = ...   -- per-build data table passed by the generated modulefile

-- The Spack env + view are built under PREFIX (outside the repo), so their
-- absolute paths are carried in the data; loading the module therefore needs
-- nothing from the repo. (Older generated tables lack these keys — fall back to
-- the historical in-repo layout so a stale modulefile keeps working.)
local repo    = d.repo_root
local name    = "lfric-apps-isambard-" .. d.variant
local spk_env = d.spack_env or (repo .. "/spack-env/" .. d.variant)
local view    = d.view or (spk_env .. "/.spack-env/view")

whatis("Name: " .. name)
whatis("LFRic Apps Spack environment (rose/cylc/psyclone/xios/...), " .. d.variant .. " stack")
help("Prebuilt LFRic Apps environment (" .. d.variant .. " variant). Puts rose/cylc/"
  .. "psyclone and the Spack view on PATH, sets SHUMLIB_ROOT/SPACK_ENV/FC/CXX/LDMPI/"
  .. "FFLAGS/LDFLAGS, and (cray variant) loads PrgEnv-gnu + the Cray HDF5/netCDF "
  .. "modules it needs — no other module load or env var required to compile/run. "
  .. "Built from " .. repo .. ". Loading the other lfric-env/* version swaps this out.")

-- --- Toolchain / MPI compiler setup -----------------------------------------
-- LFRic's Makefiles require FC (fortran.mk errors if unset), LDMPI (compile.mk
-- has no default) and CXX. For cray, the generated modulefile has already
-- load()ed PrgEnv-gnu + the Cray HDF5/netCDF modules (see the file header —
-- Lmod requires those calls at the top level, not here) before invoking this
-- file, so ftn/CC/cray-mpich are already on PATH by this point.
if d.variant == "cray" then
  setenv("FC", "ftn")
  setenv("LDMPI", "ftn")
  setenv("CXX", "CC")
else
  -- spack: the view's own mpich wrappers (wrapping gcc@14.3). lfric_core picks
  -- its per-compiler flag set from the wrapper LEAF NAME (fortran/<fc>.mk,
  -- cxx/<cxx>.mk): it ships mpif90.mk + mpic++.mk (not mpicxx.mk), so CXX must
  -- be mpic++ — not mpich's mpicxx alias, for which there is no cxx/mpicxx.mk.
  if d.mpi_fc then
    setenv("FC", d.mpi_fc)
    setenv("LDMPI", d.mpi_fc)
  end
  if d.mpi_cxx then
    setenv("CXX", d.mpi_cxx)
  end
end

-- SPACK_ENV makes `spack ...` operate on this environment, so a bare
-- `module load lfric-env/<variant>` is enough to drive spack too.
setenv("SPACK_ENV", spk_env)
prepend_path("PATH", view .. "/bin")

-- External libs merged into the view (XIOS, yaxt, shumlib, pFUnit, netCDF/HDF5
-- for the spack variant, ...) are needed to compile against this environment
-- (e.g. lfric_atm's Makefiles want XIOS's .mod files via FFLAGS and its
-- .so/.a via LDFLAGS) — mirrors what examples/minimal-compile/build.sh used to
-- add by hand. For the cray variant HDF5/netCDF are NOT in the view (Cray
-- externals); the ftn/CC wrappers loaded above supply their flags instead.
do
  local ff = "-I" .. view .. "/include"
  local cur_ff = os.getenv("FFLAGS")
  pushenv("FFLAGS", (cur_ff and cur_ff ~= "" and (cur_ff .. " " .. ff)) or ff)

  local ld = "-L" .. view .. "/lib -L" .. view .. "/lib64"
    .. " -Wl,-rpath=" .. view .. "/lib -Wl,-rpath=" .. view .. "/lib64"
  local cur_ld = os.getenv("LDFLAGS")
  pushenv("LDFLAGS", (cur_ld and cur_ld ~= "" and (cur_ld .. " " .. ld)) or ld)

  prepend_path("LIBRARY_PATH", view .. "/lib")
  prepend_path("LIBRARY_PATH", view .. "/lib64")
  prepend_path("LD_LIBRARY_PATH", view .. "/lib")
  prepend_path("LD_LIBRARY_PATH", view .. "/lib64")
end

-- Spack package scripts (e.g. psyclone) shebang the base python, whose sys.path
-- lacks the env's site-packages; put the view's site-packages on PYTHONPATH.
for _, p in ipairs(d.pythonpath) do
  prepend_path("PYTHONPATH", p)
end

-- Both cylc and rose deliberately STRIP every PYTHONPATH item from sys.path at
-- entry (cylc-flow #5124: `pythonpath_manip()`), to stop PYTHONPATH contaminating
-- their environment. That drops the view site-packages we just added, which breaks
-- them in two ways: `cylc` fails to import its deps (`ModuleNotFoundError:
-- ansimarkup`), and `rose` loses its `rose.commands` entry points so subcommands
-- vanish (`No such command: rose task-run` — fatal to the science suites, whose
-- tasks run `rose task-run`). Each re-adds its OWN pythonpath var (CYLC_PYTHONPATH /
-- ROSE_PYTHONPATH) *before* the strip, and the strip removes only one occurrence —
-- so mirroring the view site-packages into both leaves them on sys.path. Harmless
-- to other tools (they ignore these vars).
for _, p in ipairs(d.pythonpath) do
  prepend_path("CYLC_PYTHONPATH", p)
  prepend_path("ROSE_PYTHONPATH", p)
end

if d.shumlib then
  setenv("SHUMLIB_ROOT", d.shumlib)
end
if d.shumlib_lib then
  -- LDFLAGS is a space-separated flag string (not a path list): compose it and
  -- pushenv so the prior value is restored on unload. LFRic's compile.mk reads
  -- it (examples/minimal-compile/build.sh prepends the view's -L/-rpath on top of this).
  local ld  = "-L" .. d.shumlib_lib .. " -Wl,-rpath=" .. d.shumlib_lib
  local cur = os.getenv("LDFLAGS")
  if cur and cur ~= "" then
    pushenv("LDFLAGS", cur .. " " .. ld)
  else
    pushenv("LDFLAGS", ld)
  end
  prepend_path("LIBRARY_PATH", d.shumlib_lib)
  prepend_path("LD_LIBRARY_PATH", d.shumlib_lib)
end

-- Cray MPI/IO runtime libs (cray variant only; empty for spack). d.cray_libs is
-- in final front-to-back order, so prepend in reverse to preserve it (each
-- prepend pushes to the front).
for i = #d.cray_libs, 1, -1 do
  prepend_path("LD_LIBRARY_PATH", d.cray_libs[i])
end

-- python / psyclone / rose-picker are in the view, but their own prefixes are
-- prepended ahead of view/bin so the right launchers win (matches the old snippet).
if d.python then
  prepend_path("PATH", d.python .. "/bin")
end
if d.psyclone then
  prepend_path("PATH", d.psyclone .. "/bin")
  if d.psyclone_cfg then
    -- the psyclone launcher's shebang python cannot locate its config; point at it.
    setenv("PSYCLONE_CONFIG", d.psyclone_cfg)
  end
end
if d.rose_picker then
  prepend_path("PATH", d.rose_picker .. "/bin")
end

setenv("APPS_ROOT_DIR", repo .. "/vendor/lfric_apps")
setenv("CORE_ROOT_DIR", repo .. "/vendor/lfric_core")
setenv("LFRIC_TARGET_PLATFORM", d.target_platform)
setenv("FPP", d.fpp)
