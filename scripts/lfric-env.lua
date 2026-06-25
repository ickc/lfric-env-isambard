-- scripts/lfric-env.lua — LFRic Apps environment modulefile logic (Lmod / Lua).
--
-- This is the AUDITABLE half of activation. The generated per-variant modulefile
-- (working_dir/modulefiles/lfric-env/<variant>.lua, written by gen-modulefile.sh)
-- only defines a flat table of per-build paths, then runs THIS file with it:
--     assert(loadfile(".../scripts/lfric-env.lua"))(data)
-- So everything below is static and version-controlled; only the path data
-- changes per build. (Lmod's sandbox forbids dofile() and reading undeclared
-- globals, so we pass the data as an argument and read it via `...`.)
--
-- It is intentionally self-contained — only setenv / prepend_path / pushenv, no
-- nested `module load` — so loading is fast, works under /bin/sh, and the cray
-- variant carries its Cray PE lib dirs baked into LD_LIBRARY_PATH at gen time
-- (d.cray_libs); the spack variant links a from-source mpich the view RPATHs.

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
  .. "psyclone and the Spack view on PATH and sets SHUMLIB_ROOT/SPACK_ENV/... . "
  .. "Built from " .. repo .. ". Loading the other lfric-env/* version swaps this out.")

-- SPACK_ENV makes `spack ...` operate on this environment, so a bare
-- `module load lfric-env/<variant>` is enough to drive spack too.
setenv("SPACK_ENV", spk_env)
prepend_path("PATH", view .. "/bin")

-- Spack package scripts (e.g. psyclone) shebang the base python, whose sys.path
-- lacks the env's site-packages; put the view's site-packages on PYTHONPATH.
for _, p in ipairs(d.pythonpath) do
  prepend_path("PYTHONPATH", p)
end

if d.shumlib then
  setenv("SHUMLIB_ROOT", d.shumlib)
end
if d.shumlib_lib then
  -- LDFLAGS is a space-separated flag string (not a path list): compose it and
  -- pushenv so the prior value is restored on unload. LFRic's compile.mk reads
  -- it (build-lfric-atm.sh prepends the view's -L/-rpath on top of this).
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
