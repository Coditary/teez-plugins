# teez Erlang Runner

teez runner plugin for Erlang projects using [rebar3](https://rebar3.org/) with **EUnit** or **Common Test (CT)**.

## Discovery

Matches projects that contain:

- `rebar.config`, or
- any `*.app.src` file

Requires `rebar3` on `PATH`.

## Test discovery (`teez list`)

- **EUnit** (`runners.erlang.mode = "eunit"`, default): tries `rebar3 eunit --list`, then falls back to scanning `**/test/**/*.erl` (excluding `*_SUITE.erl` modules).
- **CT** (`runners.erlang.mode = "ct"`): discovers `*_SUITE.erl` modules under the project.

CLI filters (`-n`, `-t`, `-f`) are applied via teez's `filter.matches` API.

## Running tests (`teez run`)

| Mode | Command | Notes |
|------|---------|-------|
| `eunit` | `rebar3 eunit --verbose` | Parses per-function EUnit output |
| `ct` | `rebar3 ct --readable=true` | Parses `%%% SUITE ==> case: STATUS` lines |

Use `runners.erlang.mode` to switch between EUnit and CT.

## Configuration

```lua
return {
  plugins_dir = "/path/to/teez-plugins/erlang",
  plugins = { "erlang" },
  runners = {
    ["erlang"] = {
      mode = "eunit", -- or "ct"
      args = {},      -- extra rebar3 arguments appended after mode flags
      -- EUnit selection (optional)
      module = "myapp_test",
      test = "myapp_test:one+two",
      -- CT selection (optional)
      suite = "test/my_SUITE",
      group = "my_group",
      case = "my_case",
      include = { "**/test/**/*.erl", "**/*_SUITE.erl" },
      exclude = { "**/test/support/**" },
    },
  },
}
```

### Runner keys

| Key | Description |
|-----|-------------|
| `mode` | `"eunit"` (default) or `"ct"` |
| `args` | Extra arguments passed to `rebar3` |
| `module` | EUnit: `--module=` |
| `test` | EUnit: `--test=` (`Module:func1+func2`) |
| `suite` | CT: `--suite=` |
| `group` | CT: `--group=` |
| `case` | CT: `--case=` |
| `include` / `exclude` | Override manifest globs for `teez list` |

## Coverage (`teez run --with-coverage`)

Runs `rebar3 do <mode> --cover`, then collects with `rebar3 cover --verbose`.

Ensure `{cover_enabled, true}` is set in `rebar.config` (or use the `--cover` flag as above). HTML output is written under `_build/test/cover/`.

## Parsed events

| Source | Example ID | Events |
|--------|------------|--------|
| EUnit | `myapp_test:assert_true` | `start`, `pass`, `fail` |
| CT | `my_SUITE:my_case` | `pass`, `fail`, `skip` |

## Quick start

```bash
teez discover .
teez list .
teez run . --simple
```
