# teez Kotlin / Gradle Runner

teez runner plugin for Kotlin JVM projects using Gradle (`kotlin.test` / JUnit).

## Discovery

Matches projects with:

- `build.gradle.kts` or `build.gradle`
- `settings.gradle.kts` or `settings.gradle` (glob anchor)

Priority: `115`

## Requirements

One of:

- `./gradlew` in the project root (preferred)
- `gradle` on `PATH`

Manifest `requires` only checks `PATH`, so wrapper-only projects are validated in the Lua plugin instead of the JSON manifest.

## Usage

```lua
return {
  plugins_dir = "/path/to/teez-plugins/kotlin",
  plugins = { "kotlin" },
  runners = {
    kotlin = {
      project = "app",              -- optional Gradle subproject
      tests = "com.example.*",      -- optional --tests pattern(s)
      args = { "--parallel" },      -- extra Gradle args
      discover_tests = true,        -- also read JUnit XML from build/test-results
      coverage = "jacoco",          -- or "kover"
      coverage_report = "app/build/reports/jacoco/test/jacocoTestReport.xml",
      min_line_rate = 0.8,
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

## Commands

| Action | Gradle invocation |
|--------|-------------------|
| `list` | `./gradlew <project>:test --dry-run --console=plain` |
| `run` | `./gradlew <project>:test --console=plain [--tests ...]` |
| coverage | `./gradlew <project>:test jacocoTestReport` or `koverXmlReport` |

`list` returns Gradle `:test` tasks from `--dry-run`. With `discover_tests = true` (or when dry-run finds nothing), it also reads `**/build/test-results/**/TEST-*.xml` from prior runs.

## Filters

CLI filters map to Gradle `--tests` patterns:

- name filters → `*name*`
- `context.filters.pattern` → passed through as `--tests`

Post-filtering in `list` uses teez `filter.matches`.

## Output parsing

`parse_line` recognizes Gradle/JUnit console lines such as:

```
com.example.MyTest > example PASSED
com.example.MyTest > broken FAILED
```

## Coverage

Set `runners.kotlin.coverage`:

| Value | Report task | Default report path |
|-------|-------------|---------------------|
| `jacoco` | `jacocoTestReport` | `build/reports/jacoco/test/jacocoTestReport.xml` |
| `kover` | `koverXmlReport` | `build/reports/kover/report.xml` |

Override the report location with `coverage_report`. Multi-module projects usually need `project` and a module-specific `coverage_report`.
