# teez AutoHotkey (AUnit) runner

teez runner plugin for [AutoHotkey](https://www.autohotkey.com/) projects using the **AUnit** unit-test framework (AutoHotkey v2).

## Requirements

| Requirement | Notes |
|-------------|-------|
| **Windows** | AutoHotkey and AUnit are Windows-first; run teez on Windows for this runner. |
| **AutoHotkey v2** | Install from [autohotkey.com](https://www.autohotkey.com/). |
| **`AutoHotkey.exe` on `PATH`** | Manifest `requires` checks for `AutoHotkey.exe`. Add the install directory to `PATH`, or set `runners.autohotkey.command` (see below). |
| **AUnit** | Available on the script `#Include` path (default: `#Include <AUnit>`) or via `runners.autohotkey.aunit_include`. |

If you use a wrapper script named `ahk` instead of `AutoHotkey.exe`, point teez at it:

```lua
return {
  plugins_dir = "vendor/teez-plugins/autohotkey",
  plugins = { "autohotkey" },
  runners = {
    autohotkey = {
      command = "ahk", -- or full path, e.g. C:\\Program Files\\AutoHotkey\\AutoHotkey64.exe
    },
  },
}
```

## Discovery

The plugin matches projects that contain `*.ahk` files (`glob_anchors`).

Test scripts are collected from:

- `**/tests/**/*.ahk`
- `**/*_test.ahk`

Files must look like AUnit tests (contain `AUnit`, `TestCase`, `@Test`, `Assert.`, or similar). Override patterns with `runners.autohotkey.include` / `.exclude`.

## Project layout (example)

```
my-project/
├── teez.config.lua
├── lib/
│   └── MyLib.ahk
└── tests/
    └── math_test.ahk
```

Example AUnit test (`tests/math_test.ahk`):

```autohotkey
#Requires AutoHotkey v2.0
#Include <AUnit>

class MathTests extends TestCase {
    test_add() {
        Assert.Equal(3, 1 + 2)
    }
}

if (A_ScriptFullPath = A_LineFile)
    AUnit.Run()
```

## teez.config.lua

```lua
return {
  plugins_dir = "/path/to/teez-plugins/autohotkey",
  plugins = { "autohotkey" },
  runners = {
    autohotkey = {
      -- Optional: custom AutoHotkey binary
      -- command = "AutoHotkey64.exe",
      -- Optional: path to AUnit.ahk when not on library path
      -- aunit_include = "vendor/AUnit/AUnit.ahk",
      -- Optional: project-owned runner instead of generated harness
      -- runner = "tests/run.ahk",
      args = {},
      include = { "**/tests/**/*.ahk", "**/*_test.ahk" },
      exclude = {},
    },
  },
}
```

## Commands

```bash
teez discover . --json
teez list .
teez run . --simple
```

### How run works

1. If `runners.autohotkey.runner` exists, teez invokes `AutoHotkey.exe <runner> [test-id ...]`.
2. Otherwise teez generates a temporary AUnit harness that `#Include`s each discovered test file and calls `AUnit.Run()`.

Custom runners should accept test IDs as trailing arguments and print AUnit-style lines to **stdout** (see below).

## stdout protocol (`parse_line`)

The plugin maps these stdout patterns to teez events:

| Pattern | Event |
|---------|-------|
| `[TestId] PASS` | pass |
| `[TestId] FAIL: message` | fail |
| `PASS: TestId` | pass |
| `FAIL: TestId - message` | fail |
| `SKIP: TestId` | skip |

Unrecognized lines are emitted as `output`. Configure AUnit reporters accordingly, or use a custom runner that prints the formats above.

Test IDs in teez are paths relative to the project root, e.g. `tests/math_test.ahk`.

## Coverage

When `runners.autohotkey.coverage` is set, teez calls `build_coverage_run`. Pass through collect/report settings supported by your coverage tooling:

```lua
runners = {
  autohotkey = {
    coverage = {
      args = { "/coverage" },
      collect = { command = "my-ahk-coverage-tool", args = { "collect" } },
      report = "coverage/lcov.info",
      reporter = "lcov",
      output = "coverage/teez.msgpack",
      min_line_rate = 0.8,
    },
  },
},
```

AutoHotkey has no standard built-in line coverage; wire this block to your project-specific coverage wrapper.

## Manifest

| Field | Value |
|-------|-------|
| `name` | `autohotkey` |
| `requires` | `AutoHotkey.exe` |
| `glob_anchors` | `*.ahk` |
| `priority` | `115` |

## Troubleshooting

| Problem | Fix |
|---------|-----|
| Runner not discovered | Ensure at least one `.ahk` file exists in the project root tree. |
| `requires` skipped | Add AutoHotkey to `PATH` or set `runners.autohotkey.command` to the full executable path. |
| No tests listed | Check `include` patterns and that files reference AUnit/TestCase/Assert. |
| UI shows no pass/fail | AUnit output must go to **stdout** in one of the supported formats. |
