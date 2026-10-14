# teez Elixir (ExUnit) Runner

teez runner plugin for Elixir projects using [ExUnit](https://hexdocs.pm/ex_unit/ExUnit.html) via `mix test`.

## Discovery

Matches projects with `mix.exs` on disk and requires `mix` on `PATH`.

## Test IDs

`teez list` returns test file paths (and accepts `file:line` targets when passed via CLI filters), for example:

- `test/my_app/foo_test.exs`
- `test/my_app/foo_test.exs:12`

These IDs map directly to `mix test` path arguments.

## Configuration

Add the plugin directory to your project config:

```lua
return {
  plugins_dir = "/path/to/teez-plugins/elixir",
  plugins = { "elixir" },
  runners = {
    elixir = {
      -- Extra mix test arguments
      args = { "--warnings-as-errors" },

      -- ExUnit tag filter (maps to mix test --only)
      pattern = "integration",

      -- Glob patterns for test files (default: **/test/**/*_test.exs)
      include = { "test/**/*_test.exs" },
      exclude = { "test/support/**" },

      -- Enable mix test --cover
      coverage = true,
    },
  },
}
```

### Runner keys

| Key | Description |
|-----|-------------|
| `args` | Extra arguments appended to `mix test` |
| `pattern` | ExUnit tag passed as `--only <pattern>` |
| `include` | Glob patterns for test files to run |
| `exclude` | Glob patterns to skip |
| `coverage` | When true, adds `--cover` to `mix test` |

## Commands

| teez command | Under the hood |
|--------------|----------------|
| `teez list .` | Collects `*_test.exs` files under `test/` |
| `teez run .` | `mix test --color never <targets>` |
| `teez run . --with-coverage` | `mix test --cover ...` |

## Parsing

Stdout lines are mapped to teez events:

- ExUnit failure headers: `1) test name (ModuleTest)`
- Trace passes: `* test name (1.2ms)`
- Test names with module suffix: `test name (ModuleTest)`
- File locations: `test/foo_test.exs:5`
- Dot progress lines are emitted as `output` events

## Local verification

```bash
teez discover /path/to/elixir-project
teez list /path/to/elixir-project
teez run /path/to/elixir-project --simple
```
