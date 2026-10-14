# teez LabVIEW VI Tester runner

teez runner plugin for [LabVIEW](https://www.ni.com/en-us/shop/software/products/labview.html) projects that use **VI Tester** (or a compatible batch test runner VI).

## Requirements

| Requirement | Notes |
|-------------|-------|
| Windows | LabVIEW and NI toolchains are Windows-only. This plugin is not usable on Linux/macOS hosts. |
| LabVIEW install | A LabVIEW runtime or development environment must be installed. |
| `runners.labview.command` | **Required.** Executable used to launch the batch runner (for example `LabVIEW.exe`, `labview`, or a `vi-server` wrapper). |
| VI Tester batch runner | **Required.** Path to your project's batch runner VI via `runners.labview.batch_vi`. |

The manifest does **not** set teez `requires`, because the command is project-specific and must be configured in `teez.config.lua`.

## Discovery

The plugin matches projects that contain a `*.lvproj` file (`glob_anchors`).

Test files are discovered with:

- `**/Tests/**`
- `**/*Test*.vi`

Excluded by default: `**/_support/**`, `**/utilities/**`, `**/support/**`.

## Configuration

```lua
return {
  plugins_dir = "/path/to/teez-plugins/labview/..",
  plugins = { "labview" },
  runners = {
    labview = {
      -- Required: LabVIEW launcher on PATH or absolute path
      command = "C:/Program Files/National Instruments/LabVIEW 2024/LabVIEW.exe",

      -- Required: VI Tester (or compatible) batch runner VI, relative to project root
      batch_vi = "Tests/Run All Tests.vi",

      -- Optional when multiple projects exist in the target directory
      lvproj = "MyProject.lvproj",

      -- Optional LabVIEW CLI flags
      passive = true,   -- default true
      nostdwin = true,  -- hide front panel where supported
      server = false,   -- set true for vi-server style launches

      args = {},

      include = { "**/Tests/**", "**/*Test*.vi" },
      exclude = {},

      -- Coverage (requires project-specific coverage VI / tooling)
      coverage = false,
      coverage_vi = "Tests/Run Coverage.vi",
      coverage_report = "coverage/labview-coverage.xml",
      coverage_output = "coverage/teez-labview.xml",
      coverage_reporter = "junit",
      coverage_tool = "my-coverage-collector",
      coverage_tool_args = { "--input", "coverage/labview-coverage.xml" },
      min_line_rate = 0.8,
    },
  },
}
```

### Environment variables passed to the child process

| Variable | When set | Purpose |
|----------|----------|---------|
| `TEEZ_LABVIEW_TESTS` | Tests selected after filters | JSON array of test VI paths for custom batch runners |
| `TEEZ_LABVIEW_COVERAGE` | `runner.coverage = true` | Set to `"1"` during coverage runs |
| `TEEZ_LABVIEW_PROJECT` | Coverage runs | Absolute/resolved `.lvproj` path |

Your batch runner VI can read these if it supports selective execution or coverage collection.

## Commands

```bash
teez discover . --json
teez list .
teez run . --simple
teez run . --with-coverage   # when runners.labview.coverage = true
```

## How it runs

`build_command` invokes:

```text
<runner.command> -passive [-nostdwin] [-server] -root <lvproj> [runner.args...] <batch_vi> [test vi paths...]
```

- `-root` points at the discovered or configured `.lvproj`.
- Individual discovered test VIs are appended as arguments and also exported in `TEEZ_LABVIEW_TESTS`.
- Working directory defaults to the teez target path.

Adapt your VI Tester batch runner to accept appended test VI paths, or read `TEEZ_LABVIEW_TESTS`.

## Output parsing

`parse_line` understands common VI Tester / JUnit-like stdout lines:

| Example | Event |
|---------|-------|
| `PASS: Tests/Foo Test.vi::Case A (0.12 s)` | pass |
| `FAIL: Tests/Foo Test.vi::Case B: assertion failed` | fail |
| `[SKIP] Tests/Bar Test.vi` | skip |
| `PASS Tests/Foo Test.vi::Case A` | pass |
| `<testcase name="Case A" classname="Tests/Foo Test.vi" time="0.12"/>` | pass/fail/skip |

Unrecognized lines are emitted as `output` events. Only **stdout** is parsed by teez-core.

## Coverage

Enable with `runners.labview.coverage = true`.

Optional keys:

- `coverage_vi` — extra runner VI appended for coverage collection
- `coverage_collect` / `coverage_tool` — post-run collector command
- `coverage_report`, `coverage_output`, `coverage_reporter`, `min_line_rate`

Coverage behavior is project-specific; NI/VI Tester setups vary widely. Provide a batch/coverage VI and collector that match your project.

## Limitations

1. **Windows / NI only** — LabVIEW is not available on Linux or macOS CI runners without a Windows agent.
2. **No headless guarantee** — Some LabVIEW versions or VIs still require UI interaction; `-passive` / `-nostdwin` help but do not guarantee unattended runs.
3. **Command is not auto-detected** — You must set `runners.labview.command` to your LabVIEW install or wrapper.
4. **Batch runner contract** — The plugin does not ship a runner VI; you must wire `batch_vi` to your VI Tester entry point.
5. **Test case granularity** — `teez list` discovers test **VIs**, not individual VI Tester test cases inside a VI. Case-level IDs appear only when the runner prints them.
6. **Single project** — If multiple `*.lvproj` files exist, set `runners.labview.lvproj`.
7. **stderr** — teez-core does not parse stderr; ensure your runner logs results on stdout.
8. **Coverage** — No standard NI coverage CLI; integration is opt-in via project VIs and optional collector tools.
9. **`vi-server` mode** — Treat as an alternate `command`; you may need `server = true` and a wrapper script that talks to VI Server.

## Files

| File | Role |
|------|------|
| `teez-plugin-labview.json` | Manifest (`priority`: 115) |
| `teez-plugin-labview.lua` | Runner implementation |
| `README.md` | This document |
