# teez Tcl/TclTest runner

teez runner plugin for [Tcl](https://www.tcl-lang.org/) projects using the standard **tcltest** package.

## Discovery

Matches projects that contain `pkgIndex.tcl`, any `*.tcl` file, or test paths covered by the manifest `include` patterns.

Requires `tclsh` on `PATH` (use `wish` via runner config for Tk-based tests).

## Test layout

The plugin looks for:

| Pattern | Role |
|---------|------|
| `**/all.tcl` | Preferred test entry point (e.g. `tests/all.tcl`) |
| `**/*_test.tcl` | Individual test files |
| `**/tests/**/*.tcl` | Tests under a `tests/` directory |

When `all.tcl` is present it is used as the run target. Otherwise test files are sourced in one `tclsh -c` invocation with `package require tcltest`.

## Project config

```lua
return {
    plugins_dir = "/path/to/teez-plugins/tcl",
    plugins = { "tcl" },
    runners = {
        tcl = {
            -- optional: extra args appended to the tclsh invocation
            args = {},
            -- optional: run with wish instead of tclsh
            -- use_wish = true,
            -- optional: override shell binary
            -- shell = "tclsh",
            -- optional: working directory for the test process
            -- cwd = "build",
            include = { "**/tests/**", "**/*_test.tcl", "**/all.tcl" },
            exclude = { "**/pkgIndex.tcl" },
            coverage = {
                tool = "ncover",
                output = "coverage/ncover.dat",
                report = "coverage/lcov.info",
                reporter = "lcov",
                min_line_rate = 0.8,
            },
        },
    },
}
```

## Commands

```bash
teez discover . --json
teez list .
teez run . --simple
teez run . --with-coverage   # when runners.tcl.coverage is set
```

## Output parsing

Maps tcltest summary lines to teez events:

```
==== arithmetic-1.1 PASSED
==== arithmetic-1.2 Basic subtraction FAILED
```

- `==== <name> … PASSED` → pass
- `==== <name> … FAILED` → fail
- `==== <name> … SKIPPED` → skip

## Coverage

When `runners.tcl.coverage` is configured, `build_coverage_run` wraps the test command with **ncover** (or `coverage.tool`) and emits an LCOV report for teez’s coverage pipeline.

Install [ncover](https://wiki.tcl-lang.org/page/nCover) or point `coverage.tool` at another collector that supports `run` / `report` subcommands.
