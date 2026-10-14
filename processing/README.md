# processing teez runner

teez runner for [Processing](https://processing.org/) sketches tested with ProcessingUnit-style layouts.

## Requirements

- `processing-java` on `PATH` (checked via manifest `requires`)
- ProcessingUnit test sketches under `test/` or named `*Test*.pde`

## Discovery

The runner matches projects containing `*.pde` or `sketch.properties` and discovers test sketches from:

- `**/test/**`
- `**/*Test*.pde`

A sketch is listed when its main `.pde` file name matches its parent directory (Processing sketch convention), for example `test/MySketch/MySketch.pde` → id `test/MySketch`.

## Configuration

Add the plugin directory and pin the runner in `teez.config.lua`:

```lua
return {
  plugins_dir = "/path/to/teez-plugins/processing",
  plugins = { "processing" },
  runners = {
    processing = {
      -- "processing-java" (default) or "ant"
      mode = "processing-java",
      args = {},
      -- optional single sketch dir relative to target
      -- sketch = "test/MySketch",
      include = { "**/test/**", "**/*Test*.pde" },
      exclude = {},
      cwd = nil,
      coverage = {
        ant_target = "coverage",
        report = "coverage/report.xml",
        reporter = "cobertura",
        output = "coverage/teez.msgpack",
        min_line_rate = 0.8,
        collect = {
          command = "ant",
          args = { "coverage-report" },
        },
      },
    },
  },
}
```

### Run modes

| `runners.processing.mode` | Command |
|---------------------------|---------|
| `processing-java` (default) | `processing-java --run-tests <target>` |
| `ant` | `ant junit` |

When exactly one test sketch matches filters, `<target>` is that sketch directory; otherwise the project root is used.

### Coverage

Set `runners.processing.coverage` to enable `teez run --with-coverage`.

- **processing-java**: runs `processing-java --run-tests` with optional `coverage.args`; configure `collect`, `report`, and `reporter` for your coverage toolchain.
- **ant**: runs `ant coverage` (override with `coverage.ant_target`).

## Usage

```bash
teez discover /path/to/sketch-project
teez list /path/to/sketch-project
teez run /path/to/sketch-project --simple
teez run /path/to/sketch-project --with-coverage
```

## Output parsing

`parse_line` understands common JUnit-style stdout:

- Ant JUnit: `[junit] Running ...`, `[junit] TEST ... FAILED`
- Gradle/Maven: `ClassName > testName PASSED|FAILED`
- ProcessingUnit-style: `PASS testName (12ms)`, `FAIL testName message`
- Summary lines: `Tests run: N, Failures: N, ...`
