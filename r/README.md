# teez R / testthat runner

teez runner plugin for R packages that use [testthat](https://testthat.r-lib.org/).

## Discovery

Matches R package projects containing a `DESCRIPTION` file. Requires `Rscript` on `PATH`.

| Manifest field | Value |
|----------------|-------|
| Anchor | `DESCRIPTION` |
| Include | `**/testthat/**`, `**/tests/testthat/**` |
| Priority | `115` |

## Requirements

- `Rscript` on `PATH`
- R package `testthat` (for default runs)
- Optional: `devtools` when `use_devtools = true`
- Optional: `covr` and `xml2` for coverage (`--with-coverage`)

## Usage

Point teez at an R package root (where `DESCRIPTION` lives):

```bash
teez discover .
teez list .
teez run .
```

### Project config

```lua
return {
  plugins_dir = "/path/to/teez-plugins/r",
  plugins = { "r" },
  runners = {
    ["r"] = {
      -- test_dir = "tests/testthat",  -- default; auto-detected
      -- use_devtools = true,          -- devtools::test() instead of testthat::test_dir()
      -- filter = "my-test",           -- passed to testthat/devtools filter=
      -- pattern = "foo",              -- alias for filter
      coverage = {
        report = "coverage/cobertura.xml",
        output = "coverage/teez.msgpack",
        reporter = "cobertura",
        type = "tests",                 -- covr::package_coverage type
        min_line_rate = 0.8,
      },
    },
  },
}
```

## Behavior

### List

Discovers test files under `tests/testthat` (or `testthat/` when present). Test IDs are paths such as `tests/testthat/test-example.R`.

CLI filters (`-n`, `-t`, `-f`) are applied via teez's `filter.matches()` on those IDs.

### Run

By default:

```bash
Rscript -e 'testthat::test_dir("tests/testthat", reporter = "Tap", stop_on_failure = FALSE)'
```

With `use_devtools = true`:

```bash
Rscript -e 'devtools::test(reporter = "Tap", stop_on_failure = FALSE)'
```

The Tap reporter is used so stdout can be parsed into pass/fail/skip events.

### Coverage

When `runners.r.coverage` is configured (or global `coverage` is set), `teez run . --with-coverage` runs:

```r
cov <- covr::package_coverage(path = ".", type = "tests", quiet = TRUE)
covr::to_cobertura(cov, filename = "coverage/cobertura.xml")
```

Set `coverage = false` under `runners.r` to disable coverage for this runner.

## Runner options

| Key | Description |
|-----|-------------|
| `test_dir` | Override testthat directory (relative to package root or absolute) |
| `use_devtools` | Use `devtools::test()` instead of `testthat::test_dir()` |
| `filter` / `pattern` | Regex filter forwarded to testthat/devtools |
| `include` / `exclude` | Glob patterns for test file discovery in `list` |
| `env` | Extra environment variables for the Rscript process |
| `coverage` | Coverage settings table, or `false` to disable |
| `coverage.report` | Cobertura XML path (default `coverage/cobertura.xml`) |
| `coverage.output` | teez coverage output path (default `coverage/teez.msgpack`) |
| `coverage.reporter` | teez coverage reporter (default `cobertura`) |
| `coverage.type` | `covr::package_coverage()` type (default `tests`) |
| `coverage.min_line_rate` | Minimum line coverage threshold |
