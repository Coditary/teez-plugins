# teez FlexUnit Runner

Legacy/historical runner for [Adobe FlexUnit](https://github.com/flexunit/flexunit) ActionScript tests. Flex, Flash, and AIR are end-of-life; this plugin exists to support remaining brownfield projects and archival test suites.

## Requirements

There is no standalone FlexUnit CLI. The plugin checks for tools at run time based on `runners.flexunit.mode`:

| Mode | Tools on `PATH` |
|------|-----------------|
| `ant` (default) | `ant` |
| `maven` | `mvn` or `mvnw` |
| `mxmlc` | `mxmlc` or `compc`, plus `adl`, `flashplayerdebugger`, or `flashplayer` (or `player_command`) |

Manifest `requires` is intentionally omitted because projects use different toolchains (Ant vs Maven vs direct compiler invocation).

## Discovery

Matches projects with `build.xml` or `pom.xml` in the target directory.

Test files are discovered from:

- `**/*Test.as`
- `**/tests/**`

Override with `runners.flexunit.include` / `exclude`.

## Usage

Point teez at this directory:

```lua
return {
  plugins_dir = "/path/to/teez-plugins/flexunit",
  plugins = { "flexunit" },
  runners = {
    flexunit = {
      mode = "ant",
      target = "test",
      build_file = "build.xml",
    },
  },
}
```

```bash
teez discover .
teez list .
teez run . --simple
```

## Run modes

### Ant (`mode = "ant"`)

Runs `ant -f <build_file> <target>` (defaults: `build.xml`, target `test`).

```lua
runners = {
  flexunit = {
    mode = "ant",
    build_file = "build.xml",
    target = "test",
    args = { "-Dverbose=true" },
  },
}
```

### Maven (`mode = "maven"`)

Runs `mvn test` when `pom.xml` is present and no `build.xml` exists (unless `mode` is set explicitly).

### mxmlc + player (`mode = "mxmlc"`)

Compiles a FlexUnit runner entry point and records player invocation in `TEEZ_FLEXUNIT_PLAYER` for wrapper scripts:

```lua
runners = {
  flexunit = {
    mode = "mxmlc",
    runner_mxml = "src/FlexUnitApplication.mxml",
    source_path = { "src", "test" },
    library_path = { "libs" },
    output = "bin/FlexUnitTests.swf",
    player = "adl",
    app_descriptor = "src/application.xml",
    -- or: player_command = "flashplayerdebugger bin/FlexUnitTests.swf",
  },
}
```

## Coverage

Enable with `runners.flexunit.coverage = true`:

| Mode | Default target / report |
|------|-------------------------|
| `ant` | target `coverage`, report `coverage/cobertura.xml` |
| `maven` | `mvn test jacoco:report`, report `target/site/jacoco/jacoco.xml` |
| `mxmlc` | `-coverage` compiler flag + optional FlexCover collector |

Customize with `coverage_target`, `coverage_report`, `coverage_reporter`, `coverage_collect`, and `min_line_rate`.

## Output parsing

`parse_line` recognizes common FlexUnit, JUnit, and Ant `[junit]` console patterns:

- `Running com.example.MyTest`
- `Tests run: N, Failures: N, Errors: N`
- `TEST com.example.MyTest FAILED`
- `+ testMethod` / `- testMethod`
- `com.example.MyTest.testMethod PASSED`
- `Test fixture MyTest passed`

Unrecognized lines are emitted as `output` events.

## Config reference

| Key | Description |
|-----|-------------|
| `mode` | `ant`, `maven`, or `mxmlc` |
| `target` | Ant target (default `test`) |
| `build_file` | Ant build file (default `build.xml`) |
| `args` | Extra CLI arguments |
| `include` / `exclude` | Glob patterns for `list` |
| `coverage` | Enable coverage pipeline |
| `coverage_target` | Ant coverage target |
| `coverage_report` | Coverage report path |
| `compiler`, `runner_mxml`, `main_class` | mxmlc mode |
| `source_path`, `library_path` | Compiler paths |
| `player`, `player_command`, `player_args` | SWF execution |
| `env` | Extra environment variables |

## Notes

- FlexUnit 0.9, 1.x, and 4.x projects vary widely; validate `parse_line` output against your project's Ant/Maven logging.
- For CI, prefer Ant/Maven targets that already emit JUnit XML and point teez at their console output.
- This plugin is maintained for historical compatibility, not for new development.
