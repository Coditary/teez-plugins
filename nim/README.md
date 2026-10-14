# teez Nim runner

teez runner plugin for [Nim](https://nim-lang.org/) projects using the standard library `unittest` framework, typically executed via `nimble test`.

## Requirements

- `nimble` on `PATH` (also pulls in the Nim compiler)
- A `.nimble` package file in the project (discovery anchor)
- Test files matching:
  - `**/tests/**/*.nim`
  - `**/*_test.nim`

## Installation

Copy or symlink this directory into your project plugins folder:

```
my-nim-project/
├── mypkg.nimble
├── tests/
│   └── test_foo.nim
├── teez.config.lua
└── plugins/
    ├── teez-plugin-nim.json
    └── teez-plugin-nim.lua
```

Or point `plugins_dir` at this package:

```lua
return {
  plugins_dir = "/path/to/teez-plugins/nim",
  plugins = { "nim" },
}
```

## Usage

```bash
teez discover .
teez list .
teez run . --simple
teez run . --with-coverage
```

## How it works

| Phase | Behavior |
|-------|----------|
| **Discovery** | Matches projects with a `*.nimble` file (`priority: 115`) |
| **list** | Globs test files from manifest `include` patterns |
| **run** | `nimble test` for full-suite runs, or `nim c -r` per test file |
| **parse_line** | Parses Nim `unittest` stdout (`[Suite]`, `[OK]`, `[FAILED]`, `... OK`) |

### Run modes

Configure via `runners.nim.run_mode`:

| Value | Command |
|-------|---------|
| `auto` (default) | `nimble test` when a `.nimble` root is found; `nim c -r` for file-scoped runs |
| `nimble` | Always `nimble test` |
| `file` | Always `nim c -r` on discovered test files |

### Example `teez.config.lua`

```lua
return {
  plugins_dir = "plugins",
  plugins = { "nim" },
  runners = {
    ["nim"] = {
      run_mode = "auto",
      args = {},           -- extra args passed to `nimble test`
      nim_args = {},       -- extra args passed to `nim c -r`
      include = {
        "**/tests/**/*.nim",
        "**/*_test.nim",
      },
      exclude = {
        "**/vendor/**",
      },
      coverage = {
        backend = "gcov",  -- or "llvm"
        tool = "gcovr",    -- or "llvm-cov"
        report = "coverage/lcov.info",
        output = "coverage/teez.msgpack",
        reporter = "msgpack",
        min_line_rate = 0.8,
      },
    },
  },
}
```

## Coverage

`build_coverage_run` instruments tests with:

- **gcov** (default): `nim c --gcov:stdlib -r ...`, collected via `gcovr`
- **llvm**: Clang profile flags, collected via `llvm-profdata` + `llvm-cov export`

For `nimble test`, coverage flags are forwarded with `--passNimFlags:...`.

Projects using only `nimble test` should ensure the nimble `test` task runs the instrumented build, or set `run_mode = "file"` for direct `nim c -r` coverage runs.

## Test IDs

- `teez list` returns **test file paths** (for example `tests/test_foo.nim`)
- `teez run` events use **suite::test** IDs from unittest output (for example `my suite::addition`)

Filter CLI flags (`-n`, `-t`, `-f`) apply to file paths during `list` and file-based runs.

## Nimble `test` task

Most Nim packages define a `test` task in `.nimble`:

```nim
task test, "Run unit tests":
  exec "nim c -r --hints:off tests/test_all.nim"
```

If no `test` task exists, set `run_mode = "file"` so teez runs discovered test files directly.
