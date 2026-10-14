# teez D runner

teez runner plugin for [D](https://dlang.org/) projects using built-in `unittest` blocks, typically executed via `dub test` or `dmd -unittest`.

## Requirements

- `dub` on `PATH`
- A `dub.json` or `dub.sdl` file in the project (discovery anchor)
- D source files matching `**/*.d`

## Installation

Copy or symlink this directory into your project plugins folder:

```
my-d-project/
├── dub.json
├── source/
│   └── app.d
├── teez.config.lua
└── plugins/
    ├── teez-plugin-dlang.json
    └── teez-plugin-dlang.lua
```

Or point `plugins_dir` at this package:

```lua
return {
  plugins_dir = "/path/to/teez-plugins/dlang",
  plugins = { "dlang" },
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
| **Discovery** | Matches projects with `dub.json` or `dub.sdl` (`priority: 115`) |
| **list** | Grep-based discovery of `unittest` blocks in `**/*.d` (default), or `dub test --verbose` listing with `list_mode = "dub"` |
| **run** | `dub test` (default) or `dmd -unittest` when configured |
| **parse_line** | Parses D unittest stdout (`file.d:line unittest PASS/FAILED`, exceptions, summaries) |

### Run modes

Configure via `runners.dlang.run_mode`:

| Value | Command |
|-------|---------|
| `auto` (default) | `dub test` when a dub project root is found; otherwise `dmd -unittest` |
| `dub` | Always `dub test` |
| `dmd` | Always `dmd -unittest` (or `runners.dlang.compiler`) |

### Example `teez.config.lua`

```lua
return {
  plugins_dir = "plugins",
  plugins = { "dlang" },
  runners = {
    ["dlang"] = {
      run_mode = "auto",
      list_mode = "discovery", -- "discovery" (default) or "dub" (runs tests once to list)
      args = {},               -- extra args passed to `dub test`
      unittest_args = { "-v" },-- args after `dub test --`
      dflags = {},             -- extra compiler flags for dmd mode
      dmd_args = {},
      sources = {},            -- explicit .d files for dmd mode
      compiler = "dmd",        -- dmd, ldc2, or gdc
      include = {
        "**/*.d",
      },
      exclude = {
        "**/.dub/**",
      },
      coverage = {
        tool = "gcovr",              -- gcovr, llvm-cov, or lst
        build_type = "unittest-coverage",
        dflags = { "-cov" },
        dub_args = {},
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

`build_coverage_run` instruments tests via `runners.dlang.coverage`:

- **dub** (default): `dub test --build=<build_type>` (default `unittest-coverage`)
- **dmd**: `dmd -unittest -cov` (or custom `coverage.dflags`)

Collection defaults:

| `coverage.tool` | Collect step |
|-----------------|--------------|
| `gcovr` (default) | `gcovr` → LCOV report (LDC/gdc with gcov-compatible output) |
| `llvm-cov` | `llvm-profdata` + `llvm-cov export` |
| `lst` | merge DMD `.lst` coverage files |

Define a dub build type for coverage in `dub.json`:

```json
{
  "buildTypes": {
    "unittest-coverage": {
      "buildOptions": ["unittests", "coverage"],
      "dflags": ["-cov"]
    }
  }
}
```

Or use LDC with gcov:

```json
{
  "buildTypes": {
    "unittest-coverage": {
      "buildOptions": ["unittests"],
      "dflags": ["-cov=gcov"]
    }
  }
}
```

Override the collect step with `runners.dlang.coverage.collect` when your project needs a custom pipeline.

## Test IDs

- `teez list` returns `file.d:line` IDs for each discovered `unittest` block
- Named unittests (`@("name")`) appear as `file.d:line::name` when reported by the runner
- `teez run` events use the same IDs from verbose unittest output

Filter CLI flags (`-n`, `-t`, `-f`) apply to discovered test IDs during `list`.

## dmd mode

For single-file or non-dub workflows, set `run_mode = "dmd"` and optionally pin sources:

```lua
runners = {
  ["dlang"] = {
    run_mode = "dmd",
    compiler = "ldc2",
    sources = { "source/app.d" },
    dflags = { "-I=source" },
  },
}
```

## Dub unittest output

Verbose unittest output (`dub test -- -- -v`) produces lines such as:

```text
source/app.d:15 unittest PASS
source/app.d:42 unittest FAILED
core.exception.AssertError@source/app.d(44): assertion failed
4 modules passed unittests
```

teez maps these to `pass`, `fail`, and `output` events.
