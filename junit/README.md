# teez JUnit Runner Plugin

Run Java JUnit tests through **Maven Surefire** or **Gradle** from teez.

## Discovery

Matches Java projects containing any of:

- `pom.xml`
- `build.gradle`
- `build.gradle.kts`

Priority: **115** (above bundled pytest/ctest defaults for Java projects).

## Tool detection

The plugin auto-selects the build tool unless overridden:

| Condition | Tool |
|-----------|------|
| `runner.tool = "maven"` | Maven (`mvn`) |
| `runner.tool = "gradle"` | Gradle (`./gradlew` or `gradle`) |
| `./gradlew` exists | Gradle |
| `pom.xml` only | Maven |
| Gradle build files without `pom.xml` | Gradle |

Requirements at runtime:

- **Maven**: `mvn` on `PATH`
- **Gradle**: `./gradlew` in the project root, or `gradle` on `PATH`

## Usage

Add to your project `teez.config.lua`:

```lua
return {
  plugins_dir = "/path/to/teez-plugins/junit",
  plugins = { "junit" },
  runners = {
    ["junit"] = {
      tool = "auto", -- "maven", "gradle", or "auto"
      args = { "--no-daemon" }, -- Gradle/Maven extra args
      pattern = "com.example.*", -- optional test filter
      coverage = {
        report = "target/site/jacoco/jacoco.xml",
        output = "coverage/teez.msgpack",
        reporter = "cobertura",
        min_line_rate = 0.8,
      },
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

## Test listing

- **Maven**: `mvn -q test -DdryRun=true [-Dtest=pattern]`
- **Gradle**: `./gradlew test --dry-run [--tests pattern]`

Test IDs use Surefire-style notation: `com.example.MyTest#methodName`.

CLI filters (`-n`, `-f`, …) are applied after discovery via teez filter matching.

## Test execution

- **Maven**: `mvn test [-Dtest=pattern]`
- **Gradle**: `./gradlew test [--tests pattern]`

Configure extra arguments with `runners.junit.args`.

## Output parsing

`parse_line` understands common Maven Surefire and Gradle test console formats:

- `[INFO] Running com.example.MyTest`
- `[ERROR] com.example.MyTest.testSomething ... <<< FAILURE!`
- `com.example.MyTest > testSomething PASSED`
- `MyTest > testSomething() FAILED`

Unrecognized lines are emitted as `{ event = "output" }`.

## Coverage (JaCoCo)

Use `teez run . --with-coverage`.

Defaults:

| Tool | Goals | Report path |
|------|-------|-------------|
| Maven | `test`, `jacoco:report` | `target/site/jacoco/jacoco.xml` |
| Gradle | `test`, `jacocoTestReport` | `build/reports/jacoco/test/jacocoTestReport.xml` |

Override via `runners.junit.coverage`:

```lua
coverage = {
  goals = { "test", "jacoco:report" }, -- Maven
  -- goals = { "test", "jacocoTestReport" }, -- Gradle
  report = "custom/path/jacoco.xml",
  output = "coverage/teez.msgpack",
  reporter = "cobertura",
  min_line_rate = 0.85,
}
```

Your build must already apply the JaCoCo plugin (Maven `jacoco-maven-plugin` or Gradle `jacoco` plugin).

## Files

```
junit/
├── teez-plugin-junit.json
├── teez-plugin-junit.lua
└── README.md
```
