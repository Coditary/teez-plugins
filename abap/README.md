# teez ABAP runner (`abap`)

Runner plugin for [abapGit](https://abapgit.org/) repositories and SAP ABAP Unit workflows.

Discovery matches projects that contain `.abapgit.xml`. Tests are collected from abapGit-style filenames (`**/z*test*.abap`, especially `*.clas.testclasses.abap`) and from `CLASS … FOR TESTING` definitions in source.

Execution is **not** hard-wired to a SAP GUI session. Instead, the plugin shells out to a command you configure — typically [`abaplint`](https://github.com/abaplint/abaplint) with a project-specific test runner, or an ADT/CI wrapper that talks to your ABAP system.

## Requirements

The manifest does **not** set `"requires": ["abap"]`, because open-source abapGit CI usually has no SAP `abap` binary on `PATH`.

Install and configure one of these instead:

| Tool | Typical use |
|------|-------------|
| **abaplint** | Local/CI static checks + community `run-tests` integrations |
| **ADT / SAP CLI wrapper** | Push + execute ABAP Unit on a connected system |
| **Custom script** | In-house deploy-and-test pipeline |

Point `runners.abap.command` at the binary that actually runs tests in your environment.

## Quick start

```lua
-- teez.config.lua (abapGit repo root)
return {
  plugins_dir = "/path/to/teez-plugins/abap",
  plugins = { "abap" },
  runners = {
    abap = {
      -- default when omitted: command = "abaplint", args = { "run-tests" }
      command = "abaplint",
      args = { "run-tests" },
      config = "abaplint.json",
      package = "$TMP", -- optional, project-specific
    },
  },
}
```

```bash
teez discover .
teez list .
teez run . --simple
```

## Test discovery (`teez list`)

Without `runners.abap.list_command`, the plugin scans the tree:

1. Glob `**/*.abap` (respecting manifest/config include/exclude)
2. Keep files matching abapGit test naming:
   - `*.clas.testclasses.abap`
   - `z*test*` in the basename (case-insensitive)
3. Parse `CLASS zcl_example DEFINITION/IMPLEMENTATION … FOR TESTING`
4. Emit IDs as `zcl_example` or `zcl_example=>test_method` when methods are found

Apply CLI filters with `-n`, `-t`, or `-f` as usual.

### External list command

If your runner prints test IDs itself, delegate listing:

```lua
runners = {
  abap = {
    list_command = "abaplint",
    list_args = { "run-tests", "--dry-run", "--config", "abaplint.json" },
  },
}
```

## Running tests (`teez run`)

`build_command` invokes:

```
<command> <args…> [--config …] [--package …] [filter flags]
```

Defaults:

| Key | Default |
|-----|---------|
| `command` | `abaplint` |
| `args` | `{ "run-tests" }` |
| `cwd` | target project path |

### ADT / SAP system runner example

```lua
runners = {
  abap = {
    command = "./scripts/run-abap-unit.sh",
    args = {},
    env = {
      SAP_URL = os.getenv("SAP_URL"),
      SAP_CLIENT = "100",
      SAP_USER = os.getenv("SAP_USER"),
      SAP_PASSWORD = os.getenv("SAP_PASSWORD"),
    },
    filter_flag = "--grep", -- passed when CLI name filter is set
  },
}
```

Your script should print one result per line (see parsing below).

### abaplint example

```lua
runners = {
  abap = {
    command = "abaplint",
    args = { "run-tests" },
    config = "abaplint.json",
  },
}
```

Exact `run-tests` subcommand flags depend on your abaplint version and any custom runner package — adjust `args` to match.

## Output parsing

`parse_line` understands common ABAP Unit / CI formats:

| Pattern | Event |
|---------|-------|
| `PASS: zcl_test=>method` / `OK: …` / `✓ …` | `pass` |
| `FAIL: zcl_test=>method - message` / `✗ …` | `fail` |
| `SKIP: …` | `skip` |
| `START: …` / `Running …` | `start` |
| `{"status":"passed","id":"…"}` (JSON line) | normalized event |

Unrecognized lines become `output` events.

Adapt your wrapper script to emit one of these formats for reliable teez reporting.

## Coverage (`--with-coverage`)

Enable when `runners.abap.coverage` is set:

```lua
runners = {
  abap = {
    command = "abaplint",
    args = { "run-tests" },
    coverage = {
      command = "abap",           -- SAP coverage CLI or wrapper
      args = { "coverage", "export", "--format", "lcov" },
      report = "coverage/lcov.info",
      reporter = "lcov",
      output = "coverage/abap.lcov",
      min_line_rate = 0.8,
    },
  },
}
```

Keys map to teez's coverage pipeline (`collect`, `report`, `reporter`, `output`, `min_line_rate`). Use whatever SAP/ADT tool produces LCOV or another [supported reporter](https://github.com/Coditary/teez-core/wiki/Coverage-Pipeline) in your landscape.

## Config reference

| Key | Description |
|-----|-------------|
| `command` | Executable for run/list-via-core (default `abaplint`) |
| `args` | Base arguments; replaces plugin defaults when set |
| `config` | Passed as `--config <file>` when `args` not overridden |
| `package` | Passed as `--package <name>` when `args` not overridden |
| `cwd` | Working directory (default: project root) |
| `env` | Extra environment variables |
| `include` / `exclude` | Override manifest globs for discovery |
| `list_command` / `list_args` | External test listing |
| `filter_flag` | Extra flag + CLI name pattern for `-n`/`-f` |
| `test_flag` | Repeated flag + id for explicit test selection |
| `coverage` | Coverage collect/report settings |

## abapGit layout notes

Typical test artifacts:

```
src/
  zcl_my_feature.clas.abap
  zcl_my_feature.clas.testclasses.abap   # ABAP Unit tests
.abapgit.xml
abaplint.json
```

Local development loop:

1. Edit tests in abapGit structure
2. `teez list .` — verify discovery
3. `teez run .` — execute via configured runner
4. Push to Git; CI uses the same `teez.config.lua`

## Why no `"requires": ["abap"]`?

SAP's ABAP toolchain is environment-specific. abapGit contributors often only have Node/abaplint locally while ABAP Unit execution runs in CI against a licensed system. Skipping a hard `requires` entry keeps discovery working in Git checkouts while still failing clearly at run time if `command` is missing from `PATH`.

If your org standardizes on a single CLI name (e.g. always `abap`), add to a project-local manifest copy:

```json
{ "requires": ["abap"] }
```

Or wrap the binary in `runners.abap.command`.
