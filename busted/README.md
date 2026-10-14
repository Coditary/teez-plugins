# teez busted runner

[teez](https://github.com/Coditary/teez-core) runner plugin for [Busted](https://lunarmodules.github.io/busted/) Lua tests.

## Discovery

Matches projects with a `.busted` config file. Requires `busted` on `PATH`.

| Pattern | Purpose |
|---------|---------|
| `**/*_spec.lua` | Spec files by suffix |
| `**/spec/**` | Spec files under `spec/` |

## Setup

```bash
luarocks install busted
```

Add a `.busted` file in the project root (see [Busted configuration](https://lunarmodules.github.io/busted/)).

Point teez at this plugin directory:

```lua
return {
  plugins_dir = "/path/to/teez-plugins/busted",
  plugins = { "busted" },
}
```

Or copy `teez-plugin-busted.json` and `teez-plugin-busted.lua` into your project's `plugins/` directory.

## Usage

```bash
teez discover .
teez list .
teez run . --simple
```

## Configuration

`runners.busted` options (key must match manifest `name`):

```lua
return {
  runners = {
    busted = {
      -- TAP is default; use "plain" for human-readable busted output
      output = "TAP",
      verbose = false,

      -- "busted" (default) runs `busted --list`; "discovery" uses glob only
      list_mode = "busted",

      include = { "**/*_spec.lua", "**/spec/**" },
      exclude = { "**/*.teez.lua" },

      args = { "--repeat=1" },
      env = { LUA_PATH = "./src/?.lua;;" },
      cwd = "build",

      coverage = {
        collect_command = "luacov",
        collect_args = {},
        collect_cwd = ".",
        report = "luacov.report.out",
        reporter = "lcov",
        output = "coverage/teez.msgpack",
        min_line_rate = 0.8,
      },
    },
  },
}
```

CLI filters (`-n`, `-t`, `-f`) are passed to busted as `--filter=...` when possible, and applied to `teez list` results via teez's filter helper.

## List behavior

1. **`busted --list`** (default) — collects test identifiers from busted output.
2. **File discovery** — falls back to globbing `include` patterns when `--list` fails or returns nothing.
3. **`list_mode = "discovery"`** — skips `busted --list` and only returns spec file paths.

## Coverage

`teez run . --with-coverage` runs `busted --coverage` (requires [luacov](https://github.com/lunarmodules/luacov)) and then invokes the collect step from `runners.busted.coverage`.

Add a `.luacov` config in the project root, for example:

```lua
return {
  statsfile = "luacov.stats.out",
  reportfile = "luacov.report.out",
  include = { "src" },
  exclude = { "spec", "vendor" },
}
```

Install luacov:

```bash
luarocks install luacov
```

## Output parsing

| `output` | Parsed events |
|----------|---------------|
| `TAP` (default) | `ok` → pass, `not ok` → fail, `# SKIP` → skip |
| `plain` | `●` → pass, `✱` → fail, `◼` / `◆` → skip |

Unrecognized lines are emitted as `output` events.
