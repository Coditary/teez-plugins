# teez GDL / IDL Runner

teez runner plugin for [GDL](https://gnudatalanguage.github.io/) (GNU Data Language) and IDL-compatible scientific/CAD scripting projects.

GDL and IDL use `.pro` procedure files and `.dlm` modules. This plugin discovers test procedures, runs them via `gdl -e "run_tests"` (or `idl`), and parses structured pass/fail lines from stdout.

> **Note:** GDL/IDL testing is niche and often project-specific. There is no universal unit-test framework like pytest. Your `run_tests` procedure should print teeZ-friendly lines (see below) or follow the supported output patterns.

## Discovery

The runner matches projects containing `*.pro` or `*.dlm` files and discovers tests under:

- `**/tests/**`
- `**/*_test.pro`

Requires `gdl` or `idl` on `PATH`. The manifest omits `requires` because teez checks every listed binary; set `runners.gdl.gdl = "idl"` on IDL-only installs.

## Usage

Point teez at this plugin directory:

```lua
return {
  plugins_dir = "/path/to/teez-plugins/gdl",
  plugins = { "gdl" },
}
```

Or copy `teez-plugin-gdl.json` and `teez-plugin-gdl.lua` into your project `plugins/` directory.

```bash
teez discover .
teez list .
teez run . --simple
```

## How tests run

**Single test file** (default when one `*_test.pro` is found):

```bash
gdl -e "run_tests" path/to/tests/foo_test.pro
```

**Batch driver** when a bootstrap script exists (`run_tests.pro`, `scripts/run_tests.pro`, etc.) or `runners.gdl.command` is set:

```bash
gdl run_tests.pro
```

Override the batch path with `runners.gdl.command` or `runners.gdl.script`.

## Configuration

```lua
return {
  plugins = { "gdl" },
  runners = {
    gdl = {
      -- Executable: gdl (default) or idl for proprietary IDL installs
      gdl = "gdl",
      idl = "idl",

      -- Batch driver relative to target directory
      command = "run_tests.pro",

      -- Procedure goal passed to -e (default: run_tests)
      goal = "run_tests",

      -- Entry file when the target is a directory with multiple tests
      entry = "tests/all_tests.pro",

      -- Extra flags before script / -e arguments
      args = { "-quiet" },

      -- Override discovery patterns
      include = { "**/tests/**", "**/*_test.pro" },
      exclude = { "**/examples/**" },

      -- Enable coverage instrumentation on normal runs
      coverage = true,
      coverage_goal = "run_tests, /COVERAGE",

      -- Used by teez run --with-coverage (requires coverage = true)
      coverage_report = "coverage/gdl.lcov",
      coverage_reporter = "lcov",
      coverage_output = "coverage/teez.msgpack",
      min_line_rate = 0.8,
    },
  },
}
```

### Coverage

When `runners.gdl.coverage` is set, normal runs set `TEEZ_GDL_COVERAGE=1` and use `coverage_goal` (default `run_tests, /COVERAGE`) for IDL-style coverage hooks.

`build_coverage_run` is only returned when `runners.gdl.coverage` is enabled, for `teez run --with-coverage`. Configure a post-run `collect` step when your toolchain emits coverage artifacts:

```lua
runners = {
  gdl = {
    coverage = {
      report = "coverage/gdl.lcov",
      collect = { command = "gcovr", args = { "-r", ".", "--lcov", "-o", "coverage/gdl.lcov" } },
    },
  },
},
```

## Test output format

Print one line per test from your `run_tests` procedure. teeZ recognizes:

```
TEEZ PASS test_name
TEEZ FAIL test_name: assertion message
PASS: test_name
FAIL: test_name: message
OK test_name
FAILED test_name: message
Test test_name PASSED
Test test_name FAILED: message
START: test_name
SKIP: test_name
```

## Example test file

```idl
pro foo_test
  x = 1 + 1
  if x ne 2 then begin
    print, 'TEEZ FAIL foo_test: expected 2, got ', x
    return
  endif
  print, 'TEEZ PASS foo_test'
end

pro run_tests
  foo_test
end
```

Run with:

```bash
gdl -e "run_tests" tests/foo_test.pro
```
