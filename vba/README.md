# teez VBA runner (`vba`)

Runner plugin for [Rubberduck](https://rubberduckvba.com/)-style VBA unit tests. teez discovers test modules on disk and delegates execution to a configurable Windows test harness.

## Platform limitations

| Topic | Notes |
|-------|-------|
| **OS** | VBA hosts (Excel, Word, Access, …) and Rubberduck run on **Windows only**. This plugin can be installed on any teez host, but `teez run` for VBA projects is expected to run on Windows with the Office app and test runner available. |
| **Rubberduck** | Rubberduck is a VBE add-in; it does not ship a single cross-platform CLI. Set `runners.vba.command` to your wrapper (PowerShell, `rubberduck.cmd`, CI script, …). |
| **Discovery** | `teez list` scans `*Tests.bas` and files under `Tests/` and parses `@TestMethod` / `Test*` procedures. Unreadable files fall back to module-level IDs. |
| **PATH** | No `requires` entry is declared because runner binaries vary by project. Configure `runners.vba.command` explicitly. |

## Discovery anchors

The runner matches when either file exists in the project root:

- `.rubberduck`
- `Rubberduck.config`

Included test paths (manifest defaults):

- `**/*Tests.bas`
- `**/Tests/**`

## Quick start

```lua
-- teez.config.lua
return {
  plugins_dir = "/path/to/teez-plugins",
  plugins = { "vba" },
  runners = {
    ["vba"] = {
      command = "powershell",
      args = { "-File", "tools/run-rubberduck-tests.ps1" },
      run_subcommand = nil, -- omit when the script needs no subcommand
      cwd = ".",
    },
  },
}
```

```powershell
# Example wrapper (project-specific)
# tools/run-rubberduck-tests.ps1
# Emit one line per test: PASS Module.TestName  or  FAIL Module.TestName: message
```

```bash
teez discover .
teez list .
teez run . --simple
```

## Configuration (`runners.vba`)

| Key | Description |
|-----|-------------|
| `command` | Executable for run/list/coverage (default: `rubberduck`) |
| `args` | Base args prepended to every invocation |
| `run_args` / `list_args` | Extra args for run vs list |
| `run_subcommand` / `list_subcommand` | Inserted after base args (defaults: `run` / `list`) |
| `list_command` | Alternate binary for `build_list_command` when discovery should come from the harness |
| `cwd` | Working directory for child processes |
| `env` | Extra environment variables |
| `filter_flag` | CLI flag followed by JSON-encoded `context.filters` |
| `filters_env` | Env var name for JSON-encoded filters (e.g. `TEEZ_FILTERS`) |
| `include` / `exclude` | Override manifest globs for discovery |
| `coverage` | Coverage spec (see below) |
| `coverage_flag` | Flag appended during `--with-coverage` when `coverage.flag` is not set |

### Coverage (`runners.vba.coverage`)

Enable with a table (or `true` for defaults):

```lua
runners = {
  ["vba"] = {
    command = "powershell",
    args = { "-File", "tools/run-rubberduck-tests.ps1", "--coverage" },
    coverage = {
      report = "coverage/vba-lcov.info",
      reporter = "lcov",
      output = "coverage/teez.msgpack",
      min_line_rate = 0.8,
      collect_command = "powershell",
      collect_args = { "-File", "tools/collect-vba-coverage.ps1" },
    },
  },
}
```

When `coverage` is set, the plugin implements `build_coverage_run` for `teez run --with-coverage`.

## Test IDs

IDs use `ModuleName.TestMethod` (Rubberduck convention), e.g. `CalculatorTests.ShouldAddTwoNumbers`.

If a `.bas` file cannot be parsed, the module stem is listed instead (`CalculatorTests`).

## Parsed output formats

`parse_line` accepts Rubberduck- and JUnit-inspired single-line events:

```
PASS CalculatorTests.ShouldAdd
FAIL CalculatorTests.ShouldDivide: division by zero
SKIP CalculatorTests.Ignored
START CalculatorTests.ShouldAdd
[PASS] CalculatorTests.ShouldAdd
[FAIL] CalculatorTests.ShouldDivide: message
ok 1 CalculatorTests.ShouldAdd
not ok 2 CalculatorTests.ShouldDivide - message
CalculatorTests.ShouldAdd ... Passed
CalculatorTests.ShouldDivide ... Failed: message
Test 'CalculatorTests.ShouldAdd' passed
```

Configure your wrapper to print one of these formats on stdout. stderr is not parsed by teez.

## Rubberduck test modules

Typical Rubberduck layout:

```vba
'@TestModule
'@IgnoreModule
Private Assert As Object

'@TestMethod
Private Sub ShouldAddTwoNumbers()
    Assert.AreEqual 4, 2 + 2
End Sub
```

Place modules in `*Tests.bas` or under `Tests/`.

## See also

- [teez plugin development (AGENTS.md)](https://github.com/Coditary/teez-core/wiki)
- [Rubberduck unit testing](https://rubberduckvba.com/UnitTesting)
