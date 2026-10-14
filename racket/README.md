# teez Racket runner

teez runner plugin for [Racket](https://racket-lang.org/) projects using **rackunit** tests via `raco test`.

## Discovery

Matches Racket packages that contain `info.rkt` and `raco` on `PATH`.

Test files (default):

- `**/test/**`
- `**/*-test.rkt`
- `**/*_test.rkt`

## Usage

Add the plugin directory to your project config:

```lua
return {
  plugins_dir = "/path/to/teez-plugins/racket",
  plugins = { "racket" },
}
```

Or copy `teez-plugin-racket.json` and `teez-plugin-racket.lua` into your project's `plugins/` directory.

```bash
teez discover .
teez list .
teez run . --simple
```

## Configuration

`runners.racket` keys (manifest name is `racket`):

| Key | Description |
|-----|-------------|
| `args` | Extra arguments passed to `raco test` (before targets) |
| `targets` | Explicit test paths/modules (default: project root or filtered list) |
| `include` / `exclude` | Glob patterns for file discovery in `list` fallback |
| `quiet` | If true, do not add `-v` (verbose output helps event parsing) |
| `check_stderr` | Pass `--check-stderr` to `raco test` |
| `cwd` | Working directory for the test command |
| `env` | Extra environment variables |
| `coverage` | Enable coverage via the package `cover` submodule (see below) |

Example:

```lua
return {
  plugins = { "racket" },
  runners = {
    racket = {
      args = { "--check-stderr" },
      exclude = { "**/slow/**" },
    },
  },
}
```

## Listing tests

`teez list` prefers:

```bash
raco test --list <target>
```

If that yields no modules, the plugin discovers `*.rkt` files matching the include patterns under the target path.

CLI filters (`-n`, `-t`, `-f`) are applied to discovered test IDs.

## Coverage

Set `runners.racket.coverage` to collect coverage with the Racket **cover** package submodule (default name: `cover`).

Your package should define a cover submodule, for example in `info.rkt` or a test module:

```racket
(module+ cover
  (require cover))
```

Config examples:

```lua
runners = {
  racket = {
    coverage = "cover", -- submodule name
  },
}
```

```lua
runners = {
  racket = {
    coverage = {
      submodule = "cover",
      report = "coverage/lcov.info",
      reporter = "lcov",
      exclude = { "tests/helpers" },
      min_line_rate = 0.8,
    },
  },
}
```

With coverage enabled, teez runs `raco test` and then `raco cover ++<submodule>` to produce the report.

## Requirements

- [Racket](https://download.racket-lang.org/) with `raco` on `PATH`
- rackunit tests runnable via `raco test`
- For coverage: `raco pkg install cover` and a `(module+ cover ...)` submodule
