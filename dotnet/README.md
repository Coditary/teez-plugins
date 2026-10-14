# teez dotnet runner

teez runner plugin for [.NET test projects](https://learn.microsoft.com/dotnet/core/tools/dotnet-test) using `dotnet test`. Supports MSTest, xUnit, and NUnit through the shared .NET test platform.

## Discovery

The plugin matches projects that contain a `*.sln` or `*.csproj` file and requires `dotnet` on `PATH`.

| Manifest field | Value |
|----------------|-------|
| `name` | `dotnet` |
| `requires` | `dotnet` |
| `glob_anchors` | `*.sln`, `*.csproj` |
| `include` | `**/*Tests.cs`, `**/*.Tests/**` |
| `priority` | `115` |

## Usage

Add the plugin directory to your project config:

```lua
return {
  plugins_dir = "/path/to/teez-plugins/dotnet",
  plugins = { "dotnet" },
  runners = {
    dotnet = {
      -- optional runner-specific settings
      configuration = "Release",
      -- filter = "FullyQualifiedName~MyNamespace",
      -- project = "tests/MyApp.Tests/MyApp.Tests.csproj",
      -- solution = "MyApp.sln",
      -- no_build = true,
      -- args = { "--verbosity", "normal" },
    },
  },
}
```

Then:

```bash
teez discover .
teez list .
teez run . --simple
teez run . --with-coverage
```

## Commands

| Operation | Command |
|-----------|---------|
| List | `dotnet test --list-tests` |
| Run | `dotnet test --logger "console;verbosity=detailed"` |
| Coverage | `dotnet test --collect:"XPlat Code Coverage"` |

When multiple solutions or projects exist in the target directory, the plugin prefers:

1. An explicit `runners.dotnet.solution` or `runners.dotnet.project`
2. A single `*.sln`
3. A single test-like `*.csproj` (`*Tests.csproj` / `*.Tests.csproj`)
4. Otherwise the first matching project, or `.` as fallback

## Event parsing

`parse_line` maps detailed console logger output from xUnit, MSTest, and NUnit:

```text
  Passed MyApp.Tests.CalculatorTests.AddsNumbers [12 ms]
  Failed MyApp.Tests.CalculatorTests.DividesByZero [3 ms]
  Skipped MyApp.Tests.CalculatorTests.IgnoredCase
```

Test IDs are the fully qualified names emitted by `dotnet test --list-tests`.

## Filters

CLI filters are translated to `dotnet test --filter` expressions:

- name/pattern filters become `FullyQualifiedName~...`
- exact id filters become `FullyQualifiedName=...`
- multiple name filters are combined with `|`

You can also set a raw filter in config:

```lua
runners = {
  dotnet = {
    filter = "Category=Unit",
  },
}
```

## Coverage

`--with-coverage` runs:

```bash
dotnet test --collect:"XPlat Code Coverage" --results-directory TestResults
```

Coverage output is read from `TestResults/**/coverage.cobertura.xml` and written to `coverage/coverage.cobertura.xml`.

For LCOV or HTML reports, convert the Cobertura output with [ReportGenerator](https://github.com/danielpalme/ReportGenerator) or your CI tooling.

## Supported `runners.dotnet` keys

| Key | Description |
|-----|-------------|
| `project` | Explicit `.csproj` path |
| `solution` | Explicit `.sln` path |
| `configuration` | Build configuration, e.g. `Release` |
| `framework` | Target framework moniker |
| `filter` | Raw `dotnet test --filter` expression |
| `no_build` | Pass `--no-build` |
| `args` | Extra arguments appended to `dotnet test` |
| `include` / `exclude` | Override manifest include/exclude patterns |
| `results_directory` | Coverage results directory (default: `TestResults`) |
