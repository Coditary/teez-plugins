# teez Prolog (PlUnit) Runner

teez runner plugin for [SWI-Prolog](https://www.swi-prolog.org/) projects using [PlUnit](https://www.swi-prolog.org/pldoc/doc/_SWI_/plunit.html).

## Discovery

The runner matches projects that contain `*.pl` files and discovers PlUnit tests under:

- `**/test/**`
- `**/tests/**`
- `**/*_test.pl`

Requires `swipl` on `PATH`.

## Usage

Point teez at your plugin directory:

```lua
return {
  plugins_dir = "/path/to/teez-plugins/prolog",
  plugins = { "prolog" },
}
```

Or copy `teez-plugin-prolog.json` and `teez-plugin-prolog.lua` into your project `plugins/` directory.

```bash
teez discover .
teez list .
teez run . --simple
```

## How tests run

For a single test file:

```bash
swipl -g run_tests -t halt path/to/tests/foo_test.pl
```

If a bootstrap script exists (`run_tests.pl`, `scripts/run_tests.pl`, `test/run_tests.pl`, or `tests/run_tests.pl`), teez uses:

```bash
swipl -s run_tests.pl
```

Override the script path with `runners.prolog.script`.

## Configuration

```lua
return {
  plugins = { "prolog" },
  runners = {
    prolog = {
      -- Extra swipl flags before the goal/file arguments
      args = { "--quiet" },

      -- Custom PlUnit goal (default: run_tests)
      goal = "run_tests",

      -- Bootstrap script relative to target directory
      script = "run_tests.pl",

      -- Entry file when the target is a directory with multiple tests
      entry = "tests/all_tests.pl",

      -- Override discovery patterns
      include = { "**/*_test.pl", "**/tests/**" },
      exclude = { "**/examples/**" },

      -- Enable SWI coverage wrapper on normal runs
      coverage = true,
      coverage_data = "coverage/plunit.cov",

      -- Used by teez --with-coverage (requires coverage = true)
      coverage_report = "coverage/plunit.cov",
      coverage_reporter = "json",
      coverage_output = "coverage/teez.msgpack",
      min_line_rate = 0.8,
    },
  },
}
```

### Coverage

When `runners.prolog.coverage` is set, normal runs wrap the PlUnit goal with SWI-Prolog's `library(prolog_coverage)` and save data via `cov_save_data/2`.

`build_coverage_run` is only returned when `runners.prolog.coverage` is enabled, for `teez run --with-coverage`.

## Test IDs

`teez list` returns absolute or project-relative paths to PlUnit test files. PlUnit result lines are mapped to pass/fail/skip events using the test name printed by PlUnit.

## PlUnit test files

Minimal example:

```prolog
:- begin_tests(sample).

test(true) :- true.

:- end_tests(sample).
```

Load PlUnit explicitly when needed:

```prolog
:- use_module(library(plunit)).
```
