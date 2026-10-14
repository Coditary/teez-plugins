# teez ScalaTest / sbt Runner

teez runner plugin for Scala projects using [ScalaTest](https://www.scalatest.org/) via [sbt](https://www.scala-sbt.org/).

## Discovery

Matches projects with:

- `build.sbt`

Priority: `115`

## Requirements

- `sbt` on `PATH` (checked by manifest `requires`)

## Usage

```lua
return {
  plugins_dir = "/path/to/teez-plugins/scalatest",
  plugins = { "scalatest" },
  runners = {
    scalatest = {
      project = "core",                 -- optional sbt subproject (runs core/test)
      suites = { "com.example.MySpec" }, -- optional testOnly targets
      pattern = "should work",          -- ScalaTest -z substring filter
      args = { "-mem", "2048" },        -- extra sbt CLI args
      discover_tests = true,            -- file/XML fallback when show fails
      coverage = {
        goals = { "clean", "coverage", "test", "coverageReport" },
        report = "target/scala-2.13/scoverage-report/cobertura.xml",
        reporter = "cobertura",
        output = "coverage/scalatest.msgpack",
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

## Commands

| Action | sbt invocation |
|--------|----------------|
| `list` | `sbt -batch 'show definedTestNames'` (optional) + source discovery |
| `run` | `sbt -batch test` or `sbt -batch 'testOnly ...'` |
| coverage | `sbt -batch clean coverage test coverageReport` (via `runners.scalatest.coverage`) |

### Test discovery

`list` tries these strategies in order:

1. `sbt show definedTestNames` when the project defines that setting
2. Source scan of `**/src/test/**/*.scala` for `*Spec`, `*Test`, `*Tests`, `*Suite`
3. JUnit XML under `target/**/test-reports/` from prior runs

Optional `definedTestNames` in `build.sbt`:

```scala
lazy val definedTestNames = settingKey[Seq[String]]("FQCNs of ScalaTest suites for teez")
definedTestNames := Seq(
  "com.example.MySpec",
  "com.example.OtherSuite",
)
```

## Filters

CLI filters map to sbt `testOnly` and ScalaTest `-z`:

- `filters.names` → `testOnly <name>`
- `filters.name` / `filters.pattern` / `runners.scalatest.pattern` → `-z "<pattern>"`

Post-filtering in `list` uses teez `filter.matches`.

## Output parsing

`parse_line` recognizes ScalaTest lines emitted by sbt, for example:

```
[info] MySpec:
[info] - should pass
[info] - should fail *** FAILED ***
[info]   + nested example
[info]   x broken example
```

Test IDs use `SuiteFqcn::test name`.

## Coverage

Requires the [sbt-scoverage](https://github.com/scoverage/sbt-scoverage) plugin in `project/plugins.sbt`.

Configure via `runners.scalatest.coverage`:

| Key | Default |
|-----|---------|
| `goals` | `clean`, `coverage`, `test`, `coverageReport` |
| `report` | `target/scala-2.13/scoverage-report/cobertura.xml` |
| `reporter` | `cobertura` |
| `output` | `coverage/scalatest.msgpack` |

Override `report` when your Scala version uses a different `target/scala-*` directory.
