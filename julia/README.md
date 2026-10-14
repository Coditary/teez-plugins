# teez Julia runner

Runs [Julia](https://julialang.org/) package tests via `Pkg.test()` and maps [Test.jl](https://docs.julialang.org/en/v1/stdlib/Test/) output to teez events.

## Discovery

Matches projects with a `Project.toml` anchor. Requires `julia` on `PATH`.

```json
{
  "name": "julia",
  "anchors": ["Project.toml"],
  "include": ["**/test/**", "**/test_*.jl"],
  "priority": 115
}
```

## Setup

Point `plugins_dir` at this directory (or copy the plugin files into your project `plugins/` folder):

```lua
return {
  plugins_dir = "/path/to/teez-plugins/julia",
  plugins = { "julia" },
  runners = {
    julia = {
      -- optional runner options (see below)
    },
  },
}
```

## Commands

| teez command | Julia invocation |
|--------------|------------------|
| `teez list .` | Globs `test/**/*.jl` and `test_*.jl` as test IDs |
| `teez run .` | `julia --project=. -e 'using Pkg; Pkg.test()'` |
| `teez run . -n test/foo.jl` | `julia --project=test test/foo.jl` (or `--project=.` when no `test/Project.toml`) |
| `teez run . --with-coverage` | `Pkg.test(coverage=true)` then Coverage.jl → LCOV |

## Runner options

Key under `runners.julia` (must match manifest `name`):

| Key | Description |
|-----|-------------|
| `package` | Package name for `Pkg.test("Name")` (default: read from `Project.toml`) |
| `args` | Extra `julia` CLI flags (e.g. `--threads=4`) |
| `julia_args` | Passed to `Pkg.test` as `julia_args` (child process flags) |
| `test_args` | Passed to `Pkg.test` as `test_args` (forwarded to `test/runtests.jl` as `ARGS`) |
| `include` / `exclude` | Override manifest globs for `teez list` |
| `coverage` | Coverage pipeline options table (see below) |

### Example

```lua
runners = {
  julia = {
    package = "MyPackage",
    args = { "--threads=auto" },
    test_args = { "integration" },
    coverage = {
      report = "coverage/lcov.info",
      folders = { "src", "lib" },
      min_line_rate = 0.8,
    },
  },
}
```

## Coverage

With `--with-coverage`, the plugin:

1. Runs `Pkg.test(coverage=true)` (or `coverage.trace = "/path/to/trace"` when set).
2. Collects traces with [Coverage.jl](https://github.com/JuliaCI/Coverage.jl) and writes LCOV (default `coverage/lcov.info`).

Configure via `runners.julia.coverage`:

| Key | Default | Description |
|-----|---------|-------------|
| `report` | `coverage/lcov.info` | LCOV output path |
| `output` | `coverage/teez.msgpack` | teez coverage report path |
| `reporter` | `lcov` | teez coverage reporter |
| `folders` | `{ "src" }` | Source dirs passed to `process_folder` |
| `trace` | — | Custom trace path passed to `Pkg.test(coverage=...)` |
| `pkg_test` | `true` | Set `false` to skip `Pkg.test(coverage=...)` |
| `julia_args` | — | Extra Julia flags for the test subprocess during coverage |
| `min_line_rate` | — | Minimum line coverage threshold |

## Parsed output

`parse_line` recognizes Test.jl stdout:

| Pattern | Event |
|---------|-------|
| `Test Passed` | `pass` |
| `Test Failed` / `Test Failed at …` | `fail` |
| `Error During Test` | `fail` |
| `Test Broken` | `skip` |
| `MyTests: Test Failed` | `fail` (id = testset name) |

Pkg.test status lines (`tests passed`, `Some tests did not pass`) are emitted as `output` events.

## Verify

```bash
teez discover . --json
teez list .
teez run . --simple
teez run . --with-coverage
```
