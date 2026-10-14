# teez Dart Runner Plugin

Runs [Dart `package:test`](https://pub.dev/packages/test) suites via `dart test` for projects with a `pubspec.yaml` anchor.

## Requirements

- `dart` on `PATH`
- A Dart project with tests under `test/`

## Discovery

The plugin matches when `pubspec.yaml` exists in the project directory. Test files are matched by:

- `**/test/**/*_test.dart`
- `**/test/**/*.dart`

## Usage

Add the plugin directory to your `teez.config.lua`:

```lua
return {
    plugins_dir = "/path/to/teez-plugins/dart",
    plugins = { "dart" },
    runners = {
        dart = {
            -- Optional: extra args passed to every dart test invocation
            -- args = { "--chain-stack-traces" },

            -- Optional: limit parallelism (helps expanded reporter readability)
            -- concurrency = 1,

            -- Optional: override include/exclude globs
            -- include = { "test/**" },
            -- exclude = {},

            -- Optional: coverage output directory (default: coverage)
            -- coverage_dir = "coverage",
        },
    },
}
```

Then:

```bash
teez discover .
teez list .
teez run . --simple
teez run . --with-coverage
```

## Commands

| teez action | dart command |
|-------------|--------------|
| `list` | `dart test --reporter json` (falls back to `--list --reporter json` when supported) |
| `run` | `dart test --reporter expanded` |
| coverage | `dart test --coverage=coverage` + `dart run coverage:format_coverage` |

## Test IDs

Test IDs follow the expanded reporter format:

```
test/example_test.dart: group name test name
```

Filter individual tests with teez name filters; they map to `dart test --plain-name` / `--name`.

## Output parsing

`parse_line` reads `dart test --reporter expanded` stdout and maps counter changes to events:

| Marker | Meaning |
|--------|---------|
| `+N` | passed count increased → `pass` |
| `~N` | skipped count increased → `skip` |
| `-N` | failed count increased → `fail` |
| `[E]` | error suffix on failure lines |

Lines after a failure (stack traces, assertion output) are emitted as `output` events.

## Coverage

Coverage uses Dart's built-in coverage collection:

1. `dart test --coverage=<dir>`
2. `dart run coverage:format_coverage --lcov -i <dir> -o coverage/lcov.info`

The `coverage` package must be available in the project (typically a `dev_dependency`).

## Config reference

| Key | Description |
|-----|-------------|
| `runners.dart.args` | Extra CLI arguments appended to every `dart test` call |
| `runners.dart.concurrency` | Sets `--concurrency` |
| `runners.dart.include` | Glob patterns for test files (default: manifest `include`) |
| `runners.dart.exclude` | Glob patterns to exclude |
| `runners.dart.coverage_dir` | Directory for `--coverage` (default: `coverage`) |
