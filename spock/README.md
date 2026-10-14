# teez Spock Runner Plugin

Run [Spock](https://spockframework.org/) Groovy specs through **Gradle** from teez.

## Discovery

Matches Gradle projects containing:

- `build.gradle`
- `build.gradle.kts`

Priority: **115**.

Gradle is resolved at runtime: `./gradlew` in the project (or parent) tree, otherwise `gradle` on `PATH`. No manifest `requires` entry.

## Usage

```lua
-- teez.config.lua
return {
  plugins_dir = "/path/to/teez-plugins/spock",
  plugins = { "spock" },
  runners = {
    ["spock"] = {
      project = ":app", -- optional Gradle subproject
      pattern = "com.example.*Spec", -- Gradle --tests filter
      include = { "**/src/test/groovy/**", "**/*Spec.groovy" },
      exclude = { "**/build/**" },
      discover_specs = true, -- always merge Groovy spec discovery
      args = { "--no-daemon" },
      coverage = {
        goals = { "test", "jacocoTestReport" },
        report = "build/reports/jacoco/test/jacocoTestReport.xml",
        output = "coverage/teez.msgpack",
        reporter = "cobertura",
        min_line_rate = 0.8,
      },
    },
  },
}
```

```bash
teez discover .
teez list .
teez run . --simple
teez run . --with-coverage
```

## Test listing

Primary discovery:

```bash
./gradlew test --dry-run [--tests pattern]
```

Fallback (when dry-run yields no feature IDs, or when `discover_specs = true`):

- Glob `**/src/test/groovy/**` and `**/*Spec.groovy`
- Map `src/test/groovy/com/example/MySpec.groovy` → `com.example.MySpec`
- Parse `def "feature name"` / `void "feature name"()` blocks for feature IDs

Test IDs use Gradle console notation: `com.example.MySpec > should work`.

CLI filters (`-n`, `-f`, …) are applied after discovery via teez filter matching.

## Test execution

```bash
./gradlew test [--tests pattern] --console=plain
```

Configure extra Gradle arguments with `runners.spock.args`.

## Output parsing

`parse_line` understands Gradle JUnit Platform / Spock console output:

- `com.example.MySpec > should work PASSED`
- `com.example.MySpec > should fail FAILED`
- `com.example.MySpec > ignored SKIPPED`
- `[INFO] Running com.example.MySpec`
- Surefire-style `[INFO]` / `[ERROR]` lines with timings

Unrecognized lines are emitted as `{ event = "output" }`.

## Coverage (JaCoCo)

Use `teez run . --with-coverage`.

Defaults:

| Goals | Report path |
|-------|-------------|
| `test`, `jacocoTestReport` | `build/reports/jacoco/test/jacocoTestReport.xml` |

Override via `runners.spock.coverage` (see config example above). Your build must apply the Gradle `jacoco` plugin and wire `jacocoTestReport` to the `test` task.

## Runner config keys

| Key | Description |
|-----|-------------|
| `args` | Extra flags appended to Gradle (`test`, coverage goals) |
| `pattern` | Gradle `--tests` filter (class, class.feature, or glob) |
| `project` | Gradle subproject for `:project:test` (e.g. `:app`) |
| `include` | Glob patterns for Spock spec files (discovery fallback) |
| `exclude` | Glob patterns excluded from spec discovery |
| `discover_specs` | When `true`, always merge Groovy spec file discovery |
| `coverage` | JaCoCo goals, report path, reporter, thresholds |

## Files

```
spock/
├── teez-plugin-spock.json
├── teez-plugin-spock.lua
└── README.md
```
