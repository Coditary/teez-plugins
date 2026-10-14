# teez FRUIT runner plugin

Fortran [FRUIT](https://github.com/civisanalytics/fruit) (Fortran Unit Test Infrastructure) adapter for teez. Discovers FRUIT projects via `fruit.f90`, `CMakeLists.txt`, and FRUIT-specific test layouts, then runs tests through **CTest** when a configured build tree exists, or directly via FRUIT driver executables.

## Install

Copy or symlink this directory into your project `plugins/` folder, or point `plugins_dir` at the parent of `fruit/`:

```bash
teez init .
cp -r /path/to/teez-plugins/fruit plugins/fruit
```

```lua
return {
    plugins_dir = "/path/to/teez-plugins",
    plugins = { "fruit" },
}
```

`gfortran` must be on `PATH` (manifest `requires`). For the CTest execution path, `ctest` must also be available (typically via CMake).

## Coexistence with PFUnit

Both plugins can live in the same `plugins_dir`. They are distinguished by discovery anchors:

| Runner | Priority | Typical anchors |
|--------|----------|-----------------|
| `pfunit` | 115 | `**/*pfunit*`, `**/*_pfunit_test.f90`, `**/PFUNITConfig.cmake` |
| `fruit` | 114 | `fruit.f90`, `**/fruit/**`, `**/*_fruit_test.f90` |

When both match (for example a CMake repo with both PFUnit and FRUIT tests), **pfunit wins** because its priority is higher. Pin the runner explicitly when needed:

```lua
return {
    plugins = { "fruit" },   -- or { "pfunit" }
}
```

The fruit manifest excludes PFUnit test filename patterns from `include` to reduce overlap.

## Discovery

The plugin matches when at least one anchor is present:

| Kind | Patterns |
|------|----------|
| Anchors | `CMakeLists.txt`, `fruit.f90` |
| Glob anchors | `**/fruit/**`, `**/*_fruit_test.f90` |

Fortran test files covered by `include`:

- `**/*_fruit_test.f90`
- `**/fruit_tests/**`

Priority `114` — below `pfunit` (`115`) so PFUnit takes precedence when both match.

## Execution modes

### 1. CTest (preferred for CMake projects)

When `CTestTestfile.cmake` exists in the build directory (default search: `build/`, `cmake-build-debug/`, …), teez uses:

```bash
ctest -N          # list
ctest --verbose   # run
```

Configure and build first:

```bash
cmake -B build -DCMAKE_Fortran_COMPILER=gfortran
cmake --build build
```

### 2. FRUIT driver executables

If no CTest metadata is found, the plugin discovers executables in the build directory matching `*fruit*`, `*_fruit_test`, `fruit_driver*`, or `run_fruit*`, then runs them sequentially.

Override discovery with explicit paths:

```lua
return {
    runners = {
        fruit = {
            build_dir = "cmake-build-release",
            executables = {
                "cmake-build-release/tests/my_suite_fruit_test",
            },
        },
    },
}
```

## Project configuration

```lua
return {
    plugins = { "fruit" },
    runners = {
        fruit = {
            build_dir = "build",
            config = "Debug",          -- ctest -C
            regex = "fruit",             -- ctest -R
            exclude_regex = "slow",    -- ctest -E
            parallel = 4,              -- ctest -j
            args = { "--timeout", "120" },
            driver_args = {},
            executable_globs = { "*fruit*", "*_fruit_test" },
            coverage = {
                command = "gcovr",
                report = "coverage/lcov.info",
                output = "coverage/teez.msgpack",
                reporter = "msgpack",
                min_line_rate = 0.8,
                exclude = { "tests/.*", "external/.*", "fruit/.*" },
            },
        },
    },
}
```

## Coverage

`teez run . --with-coverage` runs tests, then collects Fortran coverage with `gcovr` from the build tree. Projects must be compiled with coverage flags (for example `-fprofile-arcs -ftest-coverage`).

Configure output paths via `runners.fruit.coverage` or top-level `coverage` in `teez.config.lua`.

## Usage

```bash
teez discover .          # verify FRUIT runner match
teez list .              # ctest -N or discovered executables
teez run . --simple      # run FRUIT / CTest suite
teez run . --with-coverage
```

## Parsed output

`parse_line` recognizes:

- CTest verbose lines (`Start N:`, `Passed` / `Failed`)
- FRUIT driver output (`Test "name" ... PASSED`, `[PASS]`, `PASS:`, `PASSED -`, `Failed:`, etc.)
- FRUIT summary lines (`PASSED : N`, `FAILED : N`) as `output` events

## Notes

- Vendor `fruit.f90` or add FRUIT as a CMake submodule before building.
- For monorepos, set `build_dir` to the directory containing `CTestTestfile.cmake`.
- Pin `plugins = { "fruit" }` in CMake-only repos without FRUIT glob anchors to avoid matching unrelated CMake projects via `CMakeLists.txt` alone.
