# teez PFUnit runner plugin

Fortran [PFUnit](https://github.com/Goddard-Fortran-Community/pFUnit) adapter for teez. Discovers PFUnit projects via `CMakeLists.txt` and PFUnit-specific files, then runs tests through **CTest** when a configured build tree exists, or directly via PFUnit driver executables.

## Install

Copy or symlink this directory into your project `plugins/` folder, or install via ReqPack when packaged:

```bash
# project-local
teez init .
cp -r /path/to/teez-plugins/pfunit plugins/pfunit
```

Point `plugins_dir` at the parent of `pfunit/` if needed:

```lua
return {
    plugins_dir = "/path/to/teez-plugins",
    plugins = { "pfunit" },
}
```

`ctest` must be on `PATH` (CMake/CTest integration is the primary execution path).

## Discovery

The plugin matches when at least one anchor is present:

| Kind | Patterns |
|------|----------|
| Anchor | `CMakeLists.txt` |
| Glob anchors | `**/*pfunit*`, `**/*_pfunit_test.F90`, `**/*PfunitTest.F90`, `**/pfunit.rc`, `**/PFUNITConfig.cmake` |

Fortran test files covered by `include`:

- `**/*_pfunit_test.F90`
- `**/*PfunitTest.F90`
- `**/test_*.F90`, `**/Test*.F90`

Priority `115` — above generic CTest when both match.

## Execution modes

### 1. CTest (preferred)

When `CTestTestfile.cmake` exists in the build directory (default search: `build/`, `cmake-build-debug/`, …), teez uses:

```bash
ctest -N          # list
ctest --verbose   # run
```

### 2. PFUnit driver executables

If no CTest metadata is found, the plugin discovers executables in the build directory matching `*pfunit*`, `*_pfunit_test`, or `*PfunitTest*`, then runs them with `--verbose`.

Override discovery with explicit paths:

```lua
return {
    runners = {
        pfunit = {
            build_dir = "cmake-build-release",
            executables = {
                "cmake-build-release/tests/my_suite_pfunit_test",
            },
        },
    },
}
```

## Project configuration

```lua
return {
    plugins = { "pfunit" },
    runners = {
        pfunit = {
            build_dir = "build",
            config = "Debug",          -- ctest -C
            regex = "MySuite",         -- ctest -R
            exclude_regex = "slow",    -- ctest -E
            parallel = 4,              -- ctest -j
            args = { "--timeout", "120" },
            driver_args = { "--verbose" },
            executable_globs = { "*pfunit*" },
            coverage = {
                command = "gcovr",
                report = "coverage/lcov.info",
                output = "coverage/teez.msgpack",
                reporter = "msgpack",
                min_line_rate = 0.8,
                exclude = { "tests/.*", "external/.*" },
            },
        },
    },
}
```

## Coverage

`teez run . --with-coverage` runs tests, then collects Fortran coverage with `gcovr` from the build tree. Projects must be compiled with coverage flags (for example `-fprofile-arcs -ftest-coverage`).

Configure output paths via `runners.pfunit.coverage` or top-level `coverage` in `teez.config.lua`.

## Usage

```bash
teez discover .          # verify PFUnit runner match
teez list .              # ctest -N or discovered executables
teez run . --simple      # run PFUnit / CTest suite
teez run . --with-coverage
```

## Notes

- Configure and build the CMake project before listing or running (`cmake -B build && cmake --build build`).
- For monorepos, set `build_dir` to the directory containing `CTestTestfile.cmake`.
- Parsed output covers CTest verbose lines and common PFUnit driver formats (`Test Passed:`, `PASS:`, `[ OK ]`, etc.).
- Pin `plugins = { "pfunit" }` in CMake-only repos without PFUnit glob anchors to avoid matching unrelated CMake projects via `CMakeLists.txt`.
