# teez Wolfram Language runner

teez runner plugin for the Wolfram Language [`UnitTesting`](https://reference.wolfram.com/language/ref/unit/UnitTesting.html) package.

## Requirements

One of these executables must be on `PATH`:

- `wolframscript` (recommended for headless CI)
- `math` (Wolfram Engine / Mathematica kernel launcher)

The plugin resolves the command in that order and also accepts `wolfram` as a fallback.

## Discovery

The runner matches Wolfram paclets and packages with either anchor file:

- `PacletInfo.wl`
- `Kernel/init.m`

Test files are discovered from:

- `**/Tests/**`
- `**/*Test*.wl`

`list` returns `Test*.wl` files (plus `Tests/**/*.wl`) after applying manifest/config include and exclude patterns.

## Running tests

`teez run` uses one of these strategies:

1. **Project runner script** — if `run-tests.wl`, `scripts/run-tests.wl`, or `Tests/run-tests.wl` exists, run:

   ```bash
   wolframscript -file run-tests.wl
   ```

2. **Generated runner** — otherwise teez writes a temporary Wolfram script that executes:

   ```wolfram
   Needs["UnitTesting`"];
   TestRun["Tests"]   (* or discovered Test*.wl targets *)
   ```

   and prints `TestSummary` output lines for parsing.

## Configuration

In `teez.config.lua`:

```lua
return {
  plugins_dir = "vendor/teez-plugins/wolfram",
  plugins = { "wolfram" },
  runners = {
    wolfram = {
      tests_dir = "Tests",          -- default TestRun target when no Test*.wl files match
      test_glob = "**/Test*.wl",    -- override discovery glob
      include = { "**/Tests/**" },
      exclude = {},
      args = {},                    -- extra wolframscript args
      coverage = true,              -- enable CodeCoverageTools when available
      min_line_rate = 0.8,          -- optional threshold for --with-coverage
    },
  },
}
```

| Key | Description |
|-----|-------------|
| `tests_dir` | Directory passed to `TestRun[...]` when no individual test files are selected |
| `test_glob` | Glob used for `teez list` discovery (default: `Test*.wl` and `Tests/**/*.wl`) |
| `include` / `exclude` | Extra file patterns merged with manifest defaults |
| `args` | Additional arguments appended to the `wolframscript` invocation |
| `coverage` | When truthy, wrap `TestRun` with `CodeCoverageTools` and export JSON coverage |
| `min_line_rate` | Minimum line coverage for `teez run --with-coverage` |

## Coverage

When `runners.wolfram.coverage` is set (or `teez run --with-coverage` is used), the generated runner attempts:

```wolfram
Needs["CodeCoverageTools`"];
coverage = BeginCodeCoverage[];
summary = TestRun[...];
Export["coverage/wolfram-coverage.json", EndCodeCoverage[coverage], "JSON"];
```

Coverage output is written to `coverage/wolfram-coverage.json`. If `CodeCoverageTools` is unavailable, tests still run without coverage collection.

## Output parsing

`parse_line` maps Wolfram `TestSummary` text to teez events:

| Output line | teez event |
|-------------|------------|
| `Success   <TestID>` | `pass` |
| `Failure   <TestID>   <message>` | `fail` |
| `Error     <TestID>   <message>` | `fail` |
| `Skipped   <TestID>` | `skip` |
| `Tests run: ...` / `Test Summary` | `output` |

## Example project layout

```
MyPaclet/
├── PacletInfo.wl
├── Kernel/
│   └── init.m
├── Tests/
│   ├── TestFoo.wl
│   └── TestBar.wl
└── teez.config.lua
```

Optional custom entry point:

```wolfram
(* run-tests.wl *)
Needs["UnitTesting`"];
TestRun["Tests"]
```

## Commands

```bash
teez discover . --json
teez list .
teez run . --simple
teez run . --with-coverage   # when runners.wolfram.coverage = true
```
