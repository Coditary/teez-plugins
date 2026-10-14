# teez Pester Runner

teez runner plugin for [Pester](https://pester.dev/) (PowerShell test framework).

## Requirements

- `pwsh` (PowerShell 7+) on `PATH` — required for manifest discovery
- [Pester](https://www.powershellgallery.com/packages/Pester) 5.x module installed in the shell used to run tests
- On Windows without `pwsh`, install PowerShell 7 or change `requires` in `teez-plugin-pester.json` to `["powershell"]`

The Lua plugin falls back from `pwsh` to `powershell` at runtime when building commands.

## Discovery

The runner matches projects that contain either:

- `*.psd1` (module manifests, often used alongside Pester suites), or
- `PesterConfiguration.ps1`

Default test paths:

- `**/*.Tests.ps1`
- `**/Tests/**`

## Usage

Point `plugins_dir` at this directory (or copy these files into your project `plugins/` folder):

```lua
return {
  plugins_dir = "/path/to/teez-plugins/pester",
  plugins = { "pester" },
  runners = {
    pester = {
      -- Extra Invoke-Pester arguments appended verbatim, e.g. "-Tag Unit"
      args = {},
      include = { "**/*.Tests.ps1", "**/Tests/**" },
      exclude = {},
      coverage_dir = "coverage",
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

## Behavior

| Operation | Implementation |
|-----------|----------------|
| `list` | `Invoke-Pester -List -PassThru` → test `Path` IDs |
| `run` | `pwsh -NoProfile -Command "Invoke-Pester -Output Detailed"` |
| `parse_line` | Parses Pester detailed `[+]` / `[-]` / `[?]` result lines |
| coverage | `Invoke-Pester -CodeCoverage` with JaCoCo XML output |

### Filters

CLI filters are mapped when supported by Pester:

| teez filter | Pester flag |
|-------------|-------------|
| `name` / `pattern` | `-FullNameFilter` |
| `tag` | `-TagFilter` |

Post-filtering is also applied in `list` via `filter.matches`.

## Install Pester

```powershell
Install-Module -Name Pester -Force -SkipPublisherCheck
```

## Priority

Manifest priority is `115`, above the default pytest/worker plugins when anchors overlap in mixed repos.
