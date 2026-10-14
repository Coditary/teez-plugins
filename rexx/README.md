# teez REXX Runner Plugin

teez runner for [Regina REXX](https://regina-rexx.sourceforge.io/) projects. Discovers `*.rexx` / `*.rex` test scripts and runs them through a project test harness.

## Requirements

One of these interpreters must be on `PATH`:

- `rexx` (default; provided by most Regina installs)
- `regina` (use `runners.rexx.interpreter = "regina"`)

The manifest declares `"requires": ["rexx"]`. If only `regina` is available, either add a `rexx` symlink or pin the plugin in config and set `interpreter = "regina"`.

## Discovery

The runner matches projects containing `*.rexx` or `*.rex` files (`glob_anchors`).

Test files are collected from:

- `**/tests/**`
- `**/*_test.rexx`

Runner scripts (`tests/run.rexx`, `run.rexx`) are excluded from the test list.

## Project layout

```
my-project/
├── teez.config.lua
├── src/
│   └── lib.rexx
└── tests/
    ├── run.rexx          # test harness (required for `teez run`)
    ├── foo_test.rexx
    └── bar_test.rexx
```

### Test harness output

`tests/run.rexx` should execute tests and print one result per line on stdout:

```
START tests/foo_test.rexx
PASS tests/foo_test.rexx
FAIL tests/bar_test.rexx expected 1 got 2
SKIP tests/skip_test.rexx
```

Optional duration on pass lines: `PASS tests/foo_test.rexx 42` (milliseconds).

Environment variables set by the plugin:

| Variable | Description |
|----------|-------------|
| `TEEZ_FILTERS` | JSON-encoded CLI filters |
| `TEEZ_TEST_FILES` | Newline-separated list of discovered test files |
| `TEEZ_COVERAGE` | Set to `1` when coverage mode is active |

## Configuration

```lua
return {
    plugins_dir = "/path/to/teez-plugins/rexx",
    plugins = { "rexx" },
    runners = {
        rexx = {
            -- Interpreter: "rexx" (default) or "regina"
            interpreter = "rexx",

            -- Harness script relative to project root
            runner = "tests/run.rexx",

            -- Extra args passed to the harness
            args = {},

            -- Optional working directory
            -- cwd = "build",

            -- Include/exclude globs (merged with manifest defaults)
            include = { "**/tests/**", "**/*_test.rexx" },
            exclude = { "**/tests/run.rexx" },

            -- Coverage (for `teez run --with-coverage`)
            coverage = true,
            coverage_runner = "tests/run.rexx",
            coverage_args = { "--coverage" },
            coverage_report = "coverage/rexx-coverage.json",
            coverage_reporter = "json",
            coverage_output = "coverage/teez.msgpack",
            min_line_rate = 0.8,
        },
    },
}
```

## Commands

```bash
teez discover .          # verify runner match
teez list .              # list discovered test scripts
teez run . --simple      # run tests/run.rexx via rexx or regina -r
teez run . --with-coverage
```

### Run behavior

| Interpreter | Command |
|-------------|---------|
| `rexx` | `rexx tests/run.rexx [args...]` |
| `regina` | `regina -r tests/run.rexx [args...]` |

## Installation

Copy or symlink this directory into your project `plugins/` folder, or point `plugins_dir` at `teez-plugins/rexx` in `teez.config.lua`.
