# teez Crystal Spec runner

teez runner plugin for [Crystal Spec](https://crystal-lang.org/reference/latest/specification.html) projects (anchor: `shard.yml`).

## Requirements

- `crystal` on `PATH`
- Spec files under `spec/` (default include patterns)

## Setup

In `teez.config.lua`:

```lua
return {
  plugins_dir = "/path/to/teez-plugins/crystal",
  plugins = { "crystal" },
  runners = {
    crystal = {
      -- optional runner-specific options (see below)
    },
  },
}
```

Point `plugins_dir` at this directory (it must contain `teez-plugin-crystal.json` and `teez-plugin-crystal.lua`).

## Commands

| teez | Crystal |
|------|---------|
| `teez list` | `crystal spec --dry-run` (falls back to spec file discovery) |
| `teez run` | `crystal spec --verbose` (+ discovered spec paths) |
| `teez run --with-coverage` | `crystal spec --gcov --verbose` (unless disabled) |

## Runner options (`runners.crystal`)

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `args` | `string[]` | — | Extra arguments appended to every `crystal spec` invocation |
| `include` | `string[]` | `**/spec/**/*_spec.cr`, `**/spec/**` | Glob patterns for spec files |
| `exclude` | `string[]` | — | Glob patterns excluded after include |
| `pattern` | `string` | — | Passed as `crystal spec -e <pattern>` (example name filter) |
| `format` | `string` | — | Crystal formatter: `documentation`, `progress`, `tap`, `json` |
| `verbose` | `boolean` | `true` | When `false`, omits `--verbose` from run/coverage |
| `coverage` | `boolean` \| `table` | enable gcov | Coverage settings for `--with-coverage` |

### Coverage (`runners.crystal.coverage`)

By default, coverage runs use `crystal spec --gcov`. Set `coverage = false` to skip `--gcov`.

Table form:

```lua
crystal = {
  coverage = {
    gcov = true,           -- set false to omit --gcov
    args = { "--some-flag" },
    report = "coverage/lcov.info",
    output = "coverage/teez.msgpack",
    reporter = "msgpack",
    min_line_rate = 0.8,
    collect = { command = "gcovr", args = { "-r", ".", "--xml", "-o", "coverage.xml" } },
  },
},
```

Crystal emits gcov data when built with `--gcov`; pair with `collect` / `report` as needed for your CI.

## Output parsing

`parse_line` understands:

- **Documentation format** (Crystal default): indented example lines → `pass`
- **Failure blocks**: `1) Example description` plus following indented lines → `fail` / `output`
- **TAP** (`format = "tap"`): `ok` / `not ok` lines
- **Progress** (`.`, `F`, `*`) when used via `format = "progress"`

For richer per-example events, set `runners.crystal.format = "tap"`.

## Filters

CLI filters (`-n`, `-t`, `-f`) are applied to IDs returned from `list` (dry-run descriptions or spec file paths).

## Verify

```bash
teez discover .
teez list .
teez run . --simple
```
