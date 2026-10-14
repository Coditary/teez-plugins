# teez SASUnit Runner

teez runner plugin for [SASUnit](https://github.com/sascommunity/sasunit) projects.

## Discovery

Matches projects that contain `setup.sas` or `sasunit.setup.sas`. Test files are expected under:

- `**/tests/**/*.sas`
- `**/ex_*/*.sas`

## Requirements

- `sas` on `PATH` (or configure a custom executable, see below)

## Usage

```bash
teez discover .
teez list .
teez run . --simple
```

Point teez at this plugin directory from `teez.config.lua`:

```lua
return {
  plugins_dir = "/path/to/teez-plugins/sasunit",
  plugins = { "sasunit" },
  runners = {
    ["sasunit"] = {
      -- sas = "/opt/sas/SASFoundation/9.4/sas", -- optional custom executable
      -- driver = "run_tests.sas",              -- default batch driver
      -- log = "sasunit.log",
      -- scenario = "tests/my_scenario",        -- optional single-scenario run
      -- coverage = true,                       -- enable --with-coverage
    },
  },
}
```

## Runner options

| Key | Description |
|-----|-------------|
| `sas` / `sas_executable` | SAS binary (default: `sas` on `PATH`) |
| `driver` / `batch_driver` | Batch driver passed to `-sysin` (default: `run_tests.sas`) |
| `args` | Extra CLI args appended after `-sysin` |
| `sas_args` | Args inserted before `-sysin` |
| `log` | Optional `-log` target |
| `print` | Optional `-print` target |
| `cwd` | Working directory (default: project root) |
| `env` | Extra environment variables |
| `scenario` | Sets `SASUNIT_SCENARIO` for filtered batch runs |
| `include` / `exclude` | Override manifest glob patterns for `teez list` |
| `coverage` | Enable coverage run (`true` or options table) |

## List behavior

`teez list` discovers SASUnit scenario folders from included test files:

- `tests/<scenario>/...` → `tests/<scenario>`
- `ex_<name>/...` → `ex_<name>`

CLI filters (`-n`, `-t`, `-f`) are applied to these IDs.

## Run behavior

Runs SAS with the configured batch driver:

```text
sas -sysin <project>/run_tests.sas
```

When filters or `runners.sasunit.scenario` are set, `TEEZ_SASUNIT_FILTERS` / `SASUNIT_SCENARIO` are exported for the driver to consume.

## Coverage

With `runners.sasunit.coverage = true` (or a table), `build_coverage_run` adds `-cov` and wires teez coverage collection:

```lua
runners = {
  ["sasunit"] = {
    coverage = {
      report = "coverage/sasunit.lcov",
      reporter = "lcov",
      min_line_rate = 0.8,
      collect = {
        command = "my-coverage-tool",
        args = { "collect", "." },
      },
    },
  },
}
```

## Parsed log output

`parse_line` recognizes common SASUnit log lines:

- `Testscenario: <name> PASSED|FAILED`
- `Testfall: <name> BESTANDEN|FEHLGESCHLAGEN`
- `Test scenario "<name>" ... passed|failed`
- `*** Testcase <name>: PASS|FAIL`
- `===== Test Scenario: <name> =====` (start)
