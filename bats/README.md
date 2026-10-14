# teez Bats runner (`bats`)

teez runner plugin for [Bats](https://github.com/bats-core/bats-core) (Bash Automated Testing System).

## Discovery

Matches projects containing any of:

- `.batsrc`
- `bats.config`

Requires `bats` on `PATH`.

## Test files

- `**/*.bats`
- `**/test/**/*.bats`

## Usage

Point teez at your plugin directory:

```lua
return {
  plugins_dir = "/path/to/teez-plugins/bats",
  plugins = { "bats" },
}
```

Or copy `teez-plugin-bats.json` and `teez-plugin-bats.lua` into your project's `plugins/` directory.

```bash
teez discover .
teez list .
teez run . --simple
```

## Commands

| teez action | bats invocation |
|-------------|-----------------|
| `list` | `bats --collect -r test/` (falls back to `*.bats` glob discovery) |
| `run` | `bats -t test/` (default) or `bats -r test/` when `recursive = true` |

## Configuration

Configure via `runners.bats` in `teez.config.lua`:

```lua
return {
  runners = {
    bats = {
      test_dir = "test",       -- test directory (default: "test")
      tap = true,              -- pass -t for TAP output (default: true)
      recursive = false,         -- pass -r on run (default: false; list always uses -r)
      args = {},               -- extra bats arguments
      include = nil,           -- override manifest include globs
      exclude = nil,           -- override manifest exclude globs
      coverage = nil,            -- "kcov" or "bashcov" to wrap the run command
      coverage_dir = nil,        -- kcov output directory (default: "coverage/kcov")
      coverage_report = nil,     -- bashcov report path (default: "coverage/lcov.info")
      coverage_opts = nil,       -- extra tool-specific arguments (array)
    },
  },
}
```

Set `recursive = true` to run with `bats -t -r test/`.

### Coverage

Enable shell coverage by setting `coverage` to `kcov` or `bashcov`:

```lua
runners = {
  bats = {
    coverage = "kcov",
    coverage_dir = "coverage/kcov",
  },
},
```

For `teez run --with-coverage`, the plugin runs tests under the selected tool and reports LCOV output:

| Tool | Command shape | Report |
|------|---------------|--------|
| `kcov` | `kcov --lcov <dir> bats -t -r test/` | `<coverage_dir>/coverage/lcov.info` |
| `bashcov` | `bashcov --simple-format --skip-uncoverable <report> -- bats -t -r test/` | `coverage/lcov.info` |

Install a coverage tool in your environment:

```bash
# kcov (Fedora/RHEL)
sudo dnf install kcov

# bashcov (Ruby gem)
gem install bashcov
```

## TAP parsing

`parse_line` maps bats stdout to teez events:

| TAP line | Event |
|----------|-------|
| `ok N description` | `pass` |
| `ok N # skip reason` | `skip` |
| `not ok N description` | `fail` |
| `# ...` diagnostics | `output` |
| other lines | `output` |
