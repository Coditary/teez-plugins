# teez vlang runner

teez runner plugin for [V](https://vlang.io/) projects using `v test`.

## Discovery

Matches projects containing `v.mod`. Requires the `v` compiler on `PATH`.

Test files:

- `**/*_test.v`
- `**/tests/**/*.v`

## Usage

Point teez at a V project or set `plugins_dir` to this directory:

```lua
return {
  plugins_dir = "/path/to/teez-plugins/vlang",
  plugins = { "vlang" },
  runners = {
    vlang = {
      args = {},
      pattern = "test_add", -- optional -run filter
      include = {},
      exclude = {},
    },
  },
}
```

Commands:

```bash
teez discover .
teez list .
teez run . --simple
teez run . --with-coverage
```

## Run behavior

- `teez list` discovers test files via glob patterns and applies teez filters.
- `teez run` executes `v test -stats` on discovered paths (or the target file).
- CLI name filters map to `v test -run <pattern>`.

## Output parsing

Parses standard `v test` result lines:

```text
     OK [ 1/10]   12.345 ms  math_test.v:10:test_add
   FAIL [ 2/10]   34.567 ms  math_test.v:20:test_sub
```

Events emitted: `pass`, `fail`, `skip`, and `output` for summary lines.

## Coverage

With `--with-coverage`, teez runs `v test -stats -coverage`.

Configure output paths in `runners.vlang`:

| Key | Default |
|-----|---------|
| `coverage_report` | `lcov.info` |
| `coverage_reporter` | `lcov` |
| `coverage_output` | `coverage/lcov.info` |
| `min_line_rate` | unset |

Coverage support depends on your installed V version.
