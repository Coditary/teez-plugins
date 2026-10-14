# teez Pascal runner (FPCUnit / DUnitX)

teez runner plugin for Free Pascal projects using **FPCUnit** or **DUnitX**.

## Discovery

Matches projects containing any of:

- `*.lpi` (Lazarus)
- `*.dpr` / `*.lpr` (Delphi / Free Pascal)

Requires `fpc` on `PATH`. When a `.lpi` project is present and `lazbuild` is available, Lazarus builds are used automatically unless overridden.

Test units are discovered from:

- `**/*Test*.pas`
- `**/tests/**`

## Configuration

```lua
return {
  plugins_dir = "/path/to/teez-plugins/pascal/..",
  plugins = { "pascal" },
  runners = {
    pascal = {
      -- Framework: "fpcunit" (default) or "dunitx"
      tool = "fpcunit",

      -- Optional explicit test program (.lpr / .dpr)
      test_program = "tests/alltests.lpr",

      -- Lazarus
      use_lazbuild = true,
      lazarus_target = "RunTests",
      build_mode = "Debug",
      lazarus_output = "bin/tests",

      -- FPC build
      build_dir = ".teez/pascal",
      binary_name = "tests",
      fpc_options = { "-O2" },
      unit_paths = { "src", "tests" },
      run_args = { "-v" },

      include = { "**/*Test*.pas" },
      exclude = { "**/design/**" },

      -- Coverage (--with-coverage)
      coverage = true,
      coverage_fpc_options = { "-Pi", "-O-", "-gl" },
      coverage_output = "coverage/lcov.info",
      coverage_reporter = "lcov",
      min_line_rate = 0.8,
    },
  },
}
```

## Commands

```bash
teez discover . --json
teez list .
teez run . --simple
teez run . --with-coverage
```

## Test IDs

`teez list` returns one ID per discovered test unit (path without `.pas`), for example:

- `tests/FooTest`
- `src/FooTest`

During `teez run`, individual testcase methods are parsed from runner output:

| Tool | Example line | Event |
|------|----------------|-------|
| FPCUnit | `TFooTest.TestBar ... OK` | pass |
| FPCUnit | `TFooTest.TestBar ... FAILED: message` | fail |
| DUnitX | `[PASS] TFooTest.TestBar` | pass |
| DUnitX | `[FAIL] TFooTest.TestBar - message` | fail |

Use verbose FPCUnit output (`-v` / TextTestRunner) or DUnitX console mode for per-test events.

## Run strategy

1. Resolve test program (`test_program`, common names like `testrunner.lpr`, or `*Test*.lpr`).
2. **Lazarus** (`.lpi` + `lazbuild`): `lazbuild` target, then run test binary.
3. **FPC**: compile with `fpc`, then execute the built binary.

Set `runners.pascal.tool = "dunitx"` for DUnitX projects; the plugin adds `-dDUNITX` (FPCUnit uses `-dFPCUNIT`).
