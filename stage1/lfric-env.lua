-- stage1/lfric-env.lua — what `module load lfric-env/<version>/<variant>` does.
--
-- This is the reviewable half of the environment. The generated per-build
-- modulefile only declares a table of resolved paths and then runs this file
-- with it:
--     assert(loadfile(".../modulefiles/lfric-env.lua"))(data)
-- so everything that happens on load is right here, static and version
-- controlled. (Lmod's sandbox forbids dofile() and reading undeclared globals,
-- hence passing the data as an argument and reading it via `...`.)
--
-- THE CONTRACT. Loading this module must be sufficient to compile and run
-- against the environment, and must do nothing else. Concretely, it sets:
--   * the toolchain            FC, CXX, LDMPI, FPP, LFRIC_TARGET_PLATFORM
--   * where to find the env    PATH, PYTHONPATH (+ the cylc/rose variants),
--                              LD_LIBRARY_PATH, LIBRARY_PATH, FFLAGS, LDFLAGS,
--                              SHUMLIB_ROOT, PSYCLONE_CONFIG, SPACK_ENV
-- and nothing more. In particular it does NOT set APPS_ROOT_DIR or
-- CORE_ROOT_DIR. Those name a SOURCE TREE, which belongs to whoever is building
-- — a Rose/Cylc suite declares its own sources and extracts them itself. An
-- earlier version did set them, and it cost a user a failed build: cylc runs a
-- task's pre-script AFTER its [[[environment]]] block, so a module loaded there
-- silently overrode the suite's own CORE_ROOT_DIR and pointed the compile at
-- this repo's vendored sources instead of the ones the suite had just extracted.
-- Keep this module additive; source locations are the caller's business.
--
-- One thing this file cannot express: for the cray variant, `load()` of the
-- Cray PE modules. Lmod resolves module hierarchy by statically scanning the
-- TOP-LEVEL modulefile for load(...) calls, and a load() reached through
-- loadfile() is invisible to that scan. So gen-modulefile.sh emits those calls
-- directly into the generated file, before it calls into here; by the time this
-- runs, ftn/CC and cray-mpich are already on PATH.

local d = ...   -- the per-build data table, from the generated modulefile

local name = "lfric-apps-isambard-" .. d.variant
local view = d.view

whatis("Name: " .. name)
whatis("LFRic Apps environment (rose/cylc/psyclone/xios/...), " .. d.variant .. " stack, " .. (d.version or "?"))
help("Prebuilt LFRic Apps environment, " .. d.variant .. " variant, version " .. (d.version or "?") .. ". "
  .. "Puts rose/cylc/psyclone and the Spack view on PATH and sets the toolchain "
  .. "(FC/CXX/LDMPI/FPP), FFLAGS/LDFLAGS, SHUMLIB_ROOT and SPACK_ENV; the cray "
  .. "variant also loads the Cray PE modules it was built against. Nothing else "
  .. "is needed to compile or run against it. It does not set APPS_ROOT_DIR or "
  .. "CORE_ROOT_DIR — declare your own sources. Loading another lfric-env/* "
  .. "swaps this out.")

-- --- Toolchain --------------------------------------------------------------
-- LFRic's Makefiles require FC (fortran.mk errors without it), LDMPI (compile.mk
-- has no default) and CXX.
if d.variant == "cray" then
  -- The Cray wrappers, already on PATH from the load()s in the generated file.
  setenv("FC", "ftn")
  setenv("LDMPI", "ftn")
  setenv("CXX", "CC")
else
  -- The view's own mpich wrappers around gcc@14.3. These must be spelled
  -- exactly so: LFRic selects fortran/<fc>.mk and cxx/<cxx>.mk by the wrapper's
  -- leaf name, and it ships mpif90.mk and mpic++.mk, not mpifort.mk or mpicxx.mk.
  setenv("FC", d.mpi_fc)
  setenv("LDMPI", d.mpi_fc)
  setenv("CXX", d.mpi_cxx)
end
setenv("FPP", d.fpp)
setenv("LFRIC_TARGET_PLATFORM", d.target_platform)

-- --- The environment itself -------------------------------------------------
-- SPACK_ENV makes a bare `spack` operate on this environment (`spack find`,
-- `spack location -i ...`) without needing to know where it lives.
setenv("SPACK_ENV", d.spack_env)
prepend_path("PATH", view .. "/bin")

-- Compiling against the environment needs its headers and libraries: XIOS,
-- yaxt, shumlib, pFUnit, and (spack variant) netCDF/HDF5 are merged into the
-- view, and LFRic's Makefiles read FFLAGS/LDFLAGS to find them. For the cray
-- variant HDF5/netCDF are NOT in the view — they are Cray externals, and the
-- ftn/CC wrappers inject their flags instead.
do
  -- Compose ahead of any inherited value, so the environment's own headers and
  -- libraries win over whatever the caller's shell had set. pushenv restores
  -- the previous value on unload.
  local ff = "-I" .. view .. "/include"
  local cur_ff = os.getenv("FFLAGS")
  pushenv("FFLAGS", (cur_ff and cur_ff ~= "" and (ff .. " " .. cur_ff)) or ff)

  local ld = "-L" .. view .. "/lib -L" .. view .. "/lib64"
    .. " -Wl,-rpath=" .. view .. "/lib -Wl,-rpath=" .. view .. "/lib64"
  local cur_ld = os.getenv("LDFLAGS")
  pushenv("LDFLAGS", (cur_ld and cur_ld ~= "" and (ld .. " " .. cur_ld)) or ld)

  -- prepend_path pushes to the front, so add lib64 first to end up with
  -- lib:lib64 — matching the -L order above.
  prepend_path("LIBRARY_PATH", view .. "/lib64")
  prepend_path("LIBRARY_PATH", view .. "/lib")
  prepend_path("LD_LIBRARY_PATH", view .. "/lib64")
  prepend_path("LD_LIBRARY_PATH", view .. "/lib")
end

-- Spack's package scripts (psyclone, ...) shebang the base python, whose
-- sys.path does not include the environment's site-packages.
for _, p in ipairs(d.pythonpath) do
  prepend_path("PYTHONPATH", p)
end

-- cylc and rose both STRIP every PYTHONPATH entry from sys.path at startup
-- (cylc-flow #5124, pythonpath_manip()) so PYTHONPATH cannot contaminate them.
-- That drops the site-packages just added, and breaks both: cylc cannot import
-- its own dependencies (ModuleNotFoundError: ansimarkup), and rose loses its
-- rose.commands entry points, so `rose task-run` stops existing — fatal to any
-- suite. Each re-adds its OWN variable before the strip, and the strip removes
-- only one occurrence, so mirroring into both leaves them importable. Other
-- tools ignore these variables.
for _, p in ipairs(d.pythonpath) do
  prepend_path("CYLC_PYTHONPATH", p)
  prepend_path("ROSE_PYTHONPATH", p)
end

if d.shumlib then
  setenv("SHUMLIB_ROOT", d.shumlib)
end
if d.shumlib_lib then
  -- LDFLAGS is a flag string, not a path list, so compose and pushenv it.
  local ld  = "-L" .. d.shumlib_lib .. " -Wl,-rpath=" .. d.shumlib_lib
  local cur = os.getenv("LDFLAGS")
  pushenv("LDFLAGS", (cur and cur ~= "" and (cur .. " " .. ld)) or ld)
  prepend_path("LIBRARY_PATH", d.shumlib_lib)
  prepend_path("LD_LIBRARY_PATH", d.shumlib_lib)
end

-- Cray MPI/IO runtime libraries (cray variant only; empty for spack). The list
-- is in final front-to-back order, so prepend in reverse to preserve it.
for i = #d.cray_libs, 1, -1 do
  prepend_path("LD_LIBRARY_PATH", d.cray_libs[i])
end

-- These are in the view too, but their own prefixes go ahead of view/bin so the
-- right launcher wins.
if d.python then
  prepend_path("PATH", d.python .. "/bin")
end
if d.psyclone then
  prepend_path("PATH", d.psyclone .. "/bin")
  if d.psyclone_cfg then
    -- The psyclone launcher's shebang python cannot find its own config.
    setenv("PSYCLONE_CONFIG", d.psyclone_cfg)
  end
end
if d.rose_picker then
  prepend_path("PATH", d.rose_picker .. "/bin")
end
