# teez MATLAB runner

teez runner plugin for the [MATLAB Unit Testing Framework](https://www.mathworks.com/help/matlab/matlab-unit-test-framework.html).

## Requirements

- `matlab` on `PATH` (checked via manifest `requires`)
- MATLAB R2013a or newer with `matlab.unittest`

### GNU Octave fallback

This plugin targets the official MATLAB `matlab` executable and `runtests` API. GNU Octave is **not** supported out of the box:

- Octave does not provide a `matlab` binary unless you add a wrapper or symlink.
- `runtests`, `testsuite`, and `matlab.unittest.plugins.CodeCoveragePlugin` are MATLAB-specific.

For Octave-only projects, use a custom wrapper script on `PATH` named `matlab` that forwards to Octave, or pin another runner in `teez.config.lua`. Expect limited compatibility with MATLAB unittest classes and coverage collection.

## Discovery

The runner matches projects with:

| Signal | Pattern |
|--------|---------|
| Anchor | `+tests`, `project.prj` |
| Glob anchor | `**/*Test.m`, `**/tests/**` |

Default test file patterns:

- `**/*Test.m`
- `**/tests/**/*.m`

## Usage

Add the plugin directory to your project config:

```lua
return {
  plugins_dir = "/path/to/teez-plugins/matlab",
  plugins = { "matlab" },
  runners = {
    matlab = {
      tests_folder = "tests", -- default; also detects +tests
      -- coverage = "coverage/matlab.cov", -- enable with teez run --with-coverage
      coverage_source = "src",
    },
  },
}
```

Commands:

```bash
teez discover .
teez list .
teez run . --simple
teez run . --with-coverage   # when runners.matlab.coverage is set
```

## Behavior

- **list** — discovers `*Test.m` files and `tests/**/*.m` under the target path, applies include/exclude and CLI filters.
- **run** — executes `matlab -batch "runtests('tests')"` (or `+tests` when present). A single filtered test runs via `runtests(which('path/to/Test.m'))`.
- **parse_line** — maps MATLAB unittest stdout (`Running …`, `Failed …`, `Failure in …`, `Error occurred in …`, `Passed …`, `Done …`) to teez events.
- **coverage** — when `runners.matlab.coverage` is set (e.g. `coverage/matlab.cov`), `build_coverage_run` uses `CodeCoveragePlugin` with Cobertura output for `teez run --with-coverage`.

## Runner options

| Key | Description |
|-----|-------------|
| `tests_folder` | Folder passed to `runtests` when no specific test files are selected (default: `tests` or `+tests`) |
| `include` / `exclude` | Override manifest glob patterns for discovery |
| `coverage` | Cobertura report path (required for `--with-coverage`) |
| `coverage_source` | Source tree for line coverage (default: `.`) |
| `coverage_output` | teez coverage summary output (default: `coverage/teez.msgpack`) |
| `coverage_min_line_rate` | Minimum line rate threshold |
| `matlab_script` | Replace generated batch script entirely |
| `prelude` | MATLAB statements run before `runtests` |
| `args` | Extra arguments appended to the `matlab` invocation |
| `cwd` | Working directory for the MATLAB process |
| `env` | Extra environment variables |
