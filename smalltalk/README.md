# teez Smalltalk (SUnit) Runner

teez runner plugin for [SUnit](https://en.wikipedia.org/wiki/SUnit) test suites in Pharo, Squeak, and GNU Smalltalk projects.

## Discovery

The runner matches projects that contain:

- `package.st`
- any `*.stproj` file

Test files are expected under:

- `**/*Test*.st`
- `**/Tests/**`

## Requirements

Install a Smalltalk VM CLI on `PATH` and configure it in `teez.config.lua`:

| VM | Typical command |
|----|-----------------|
| Pharo | `pharo` |
| GNU Smalltalk | `gst-tool` |

`runners.smalltalk.command` is **required** — the plugin does not hard-require a binary in the manifest so you can choose Pharo or GST per project.

## Configuration

```lua
return {
  plugins_dir = "/path/to/teez-plugins/smalltalk",
  plugins = { "smalltalk" },
  runners = {
    ["smalltalk"] = {
      command = "pharo",
      image = "Pharo.image",
      script = "run-tests.st",
      args = {}, -- extra CLI args before image/script
      run_args = {}, -- appended for `teez run`
      list_args = {}, -- appended for `teez list`
      list_script = "list-tests.st", -- optional; defaults to `script`
      cwd = nil, -- defaults to target path
      env = {},
      include = { "**/*Test*.st", "**/Tests/**" },
      exclude = {},
      coverage = {
        script = "run-tests-with-coverage.st",
        report = "coverage/smalltalk.lcov",
        reporter = "lcov",
        output = "coverage/teez.msgpack",
        collect = { command = "lcov", args = { "--summary", "coverage/smalltalk.lcov" } },
        min_line_rate = 0.8,
      },
    },
  },
}
```

### Pharo (default layout)

`teez run` builds a command equivalent to:

```bash
pharo -headless Pharo.image -script run-tests.st
```

Extra `args` are inserted after `-headless` and before the image unless you already pass `-headless`, the image, or `-script` yourself.

### GNU Smalltalk

```lua
runners = {
  ["smalltalk"] = {
    command = "gst-tool",
    script = "run-tests.st",
  },
},
```

If no `-f` / `--file` flag is present, the plugin adds `-f <script>`.

## Listing tests

`teez list` discovers tests in two ways:

1. **Script-based** (recommended): run `list_script` (or `script`) and parse one ID per line.
2. **File-based fallback**: scan `include` globs and extract `*Test*` class names and `Class>>selector` IDs from `.st` sources.

Apply CLI filters with `-n`, `-t`, or `-f`; they are passed as `TEEZ_FILTERS` and applied to collected IDs.

### Suggested `list-tests.st` output

```
MyModelTest>>testAddsNumbers
MyServiceTest>>testCreatesRecord
```

Class-only lines are also accepted:

```
MyModelTest
```

## Running tests

Provide a project-local `run-tests.st` (or override `runners.smalltalk.script`). The script should run the SUnit suite and print machine-readable lines to **stdout**.

### Recommended stdout format

```
PASS MyModelTest>>testAddsNumbers
FAIL MyServiceTest>>testCreatesRecord: expected 2 got 3
SKIP MyLegacyTest>>testDeprecated
START MyModelTest>>testAddsNumbers
```

`parse_line` also accepts common variants:

- `passed|failed|skipped|error Class>>selector: message`
- `Class>>selector - detail`
- `FAILURE: Class>>selector - message`
- `ERROR: Class>>selector - message`

Lines that do not match a test result are emitted as `output` events. Progress dots and summary lines (`Ran N tests`, etc.) are ignored.

## Coverage

When `runners.smalltalk.coverage` is set, `teez run --with-coverage` uses `build_coverage_run`:

- Runs the coverage script (defaults to `run-tests.st`, override with `coverage.script`)
- Writes reports using `coverage.report`, `coverage.reporter`, and `coverage.output`
- Optional `coverage.collect` step for post-processing (e.g. `lcov`, custom tooling)
- Optional `coverage.min_line_rate` threshold

Your coverage script is responsible for producing the report file(s) expected by `collect`.

## Example `teez.config.lua` (Pharo)

```lua
return {
  plugins_dir = "vendor/teez-plugins/smalltalk",
  plugins = { "smalltalk" },
  runners = {
    ["smalltalk"] = {
      command = "pharo",
      image = "Pharo.image",
      script = "run-tests.st",
      list_script = "list-tests.st",
    },
  },
}
```

## Verify

```bash
teez discover . --json
teez list .
teez run . --simple
teez run . --with-coverage   # when runners.smalltalk.coverage is configured
```
