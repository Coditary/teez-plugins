# teez qtest runner

teez runner plugin for [Qt Test (QTest)](https://doc.qt.io/qt-6/qtest-overview.html) projects built with **CMake/CTest** or **qmake**.

## Discovery

Matches projects that contain:

- `CMakeLists.txt` (CMake + `enable_testing()` / `add_test()`)
- `*.pro` (qmake with `QT += testlib` / `TESTS`)

Requires `ctest` on `PATH` (from the CMake package).

## Test files

Default include patterns:

- `**/tests/**`
- `**/*_test.cpp`
- `**/*Test.qml`

## Usage

Point `plugins_dir` at this directory (or copy the plugin files into your project `plugins/` folder):

```lua
return {
    plugins_dir = "/path/to/teez-plugins/qtest",
    plugins = { "qtest" },
    runners = {
        qtest = {
            build_dir = "build",
            config = "Debug",
            verbose = true,
        },
    },
}
```

```bash
teez discover .
teez list .
teez run . --simple
teez run . --with-coverage
```

## Runner options (`runners.qtest`)

| Key | Description |
|-----|-------------|
| `build_dir` | CMake/qmake build directory (default: searches `build`, `cmake-build-debug`, …) |
| `config` | CTest build configuration passed to `-C` (e.g. `Debug`, `Release`) |
| `regex` | CTest `-R` filter for test names |
| `exclude_regex` | CTest `-E` exclusion filter |
| `parallel` | CTest parallel jobs (`-j`) |
| `verbose` | Enable verbose QTest output (`ctest -V` or `ninja test -v`) |
| `qtest_verbose` | Alias for `verbose` |
| `use_ninja` | Run via `ninja test` instead of `ctest` when `build.ninja` exists |
| `generator` | Set to `"ninja"` to auto-select `ninja test` when `build.ninja` is present |
| `args` | Extra arguments appended to the test command |
| `env` | Extra environment variables for the child process |
| `include` / `exclude` | Override manifest glob patterns for qmake discovery |
| `coverage` | Coverage collector settings (see below) |

CLI filters (`-n`, `-t`, `-f`) are applied when listing tests.

## Backends

### CMake / CTest (default)

- **List:** `ctest -N` in the build directory
- **Run:** `ctest --output-on-failure -V` (or `ninja test -v` with `use_ninja = true`)

Configure your Qt project with testing enabled:

```cmake
find_package(Qt6 REQUIRED COMPONENTS Test)
enable_testing()
add_executable(my_test tests/my_test.cpp)
target_link_libraries(my_test PRIVATE Qt6::Test)
add_test(NAME my_test COMMAND my_test)
```

### qmake

- **List:** parses `TESTS +=` entries from `*.pro` and `*_test` Makefile targets
- **Run:** `make check` with optional `TESTARGS=-v`

## Output parsing

`parse_line` understands:

- QTest: `PASS :`, `FAIL! :`, `SKIP :`, `XFAIL :`
- CTest: `N/M Test #K: name ... Passed/Failed`

## Coverage (`runners.qtest.coverage`)

Supports **gcovr** (default) and **llvm-cov**:

```lua
runners = {
    qtest = {
        build_dir = "build",
        coverage = {
            tool = "gcovr",           -- or "llvm-cov"
            report = "coverage/lcov.info",
            output = "coverage/teez.msgpack",
            reporter = "msgpack",
            min_line_rate = 0.8,
            filters = { "src/.*" },
            gcovr_args = { "--gcov-ignore-parse-errors" },
            -- llvm-cov only:
            profile = "build/default.profdata",
            objects = { "build/**" },
            llvm_cov_args = {},
        },
    },
}
```

Coverage runs tests via `ctest -V`, then collects with the configured tool.

## Files

| File | Purpose |
|------|---------|
| `teez-plugin-qtest.json` | Plugin manifest |
| `teez-plugin-qtest.lua` | Runner implementation |
