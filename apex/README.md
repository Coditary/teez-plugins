# teez Apex Runner

Salesforce Apex test runner for [teez](https://github.com/Coditary/teez-core) via the Salesforce CLI (`sf`).

## Requirements

- [Salesforce CLI](https://developer.salesforce.com/tools/salesforcecli) (`sf`) on `PATH`
- Authenticated default org (`sf org login web`) or another configured target org
- Salesforce project with `sfdx-project.json` or `sf-project.json`

## Discovery

The plugin matches Salesforce projects by anchor file and scans local Apex test sources:

| Manifest field | Value |
|----------------|-------|
| `anchors` | `sfdx-project.json`, `sf-project.json` |
| `include` | `**/classes/*Test.cls`, `**/tests/**` |
| `requires` | `sf` |
| `priority` | `115` |

`teez list` discovers tests from local `*.cls` files first. If none are found, it falls back to:

```bash
sf apex list test --json
```

Test IDs use Salesforce naming:

- `MyClassTest` — entire test class
- `MyClassTest.testCreate` — single test method

## Usage

Point teez at your Salesforce project and enable the plugin:

```lua
-- teez.config.lua
return {
  plugins_dir = "/path/to/teez-plugins",
  plugins = { "apex" },
  runners = {
    apex = {
      -- Optional Salesforce CLI args appended to every run
      args = { "--wait", "30" },

      -- Used when no explicit test IDs were discovered/filtered
      test_level = "RunLocalTests",

      -- Override default include globs
      include = { "**/classes/*Test.cls", "**/tests/**" },

      -- Coverage output directory for --with-coverage
      coverage_output_dir = "coverage/apex",
    },
  },
}
```

Run tests:

```bash
teez discover .
teez list .
teez run . --simple
teez run . --with-coverage
```

## Commands

### Run

Default command built by the plugin:

```bash
sf apex run test \
  --result-format human \
  --synchronous \
  --test-level RunLocalTests
```

When tests are discovered or filtered, the plugin switches to explicit selection:

```bash
sf apex run test \
  --result-format human \
  --synchronous \
  --tests MyClassTest,MyOtherTest.testMethod
```

### Coverage

With `--with-coverage`, teez uses:

```bash
sf apex run test \
  --result-format json \
  --synchronous \
  --code-coverage \
  --output-dir coverage/apex \
  --tests ...
```

Coverage artifacts are written under `coverage/apex/` and summarized for teez as JSON.

## Output parsing

`parse_line` supports:

- `--result-format human` table rows (`Class.method`, `Pass`/`Fail`/`CompileFail`/`Skip`)
- Single-line JSON test records when `--result-format json` is used

Human rows are mapped to teez events:

| Salesforce outcome | teez event |
|--------------------|------------|
| `Pass` | `pass` |
| `Fail`, `CompileFail` | `fail` |
| `Skip` | `skip` |

## Filters

CLI filters (`-n`, `-t`, `-f`) are applied in `list` and when building `--tests`. Filter semantics follow teez-core's `filter.matches()` helper.

## Notes

- `--test-level` and `--tests` are mutually exclusive; the plugin prefers `--tests` when it has discovered or filtered IDs.
- Method-level IDs take precedence over their containing class to avoid duplicate execution.
- Local discovery parses `@IsTest` annotations; org fallback requires a logged-in Salesforce org.
