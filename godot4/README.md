# teez Godot 4 runner

[teez](https://github.com/Coditary/teez-core) runner plugin for **Godot 4 built-in unit tests** (editor test runner, Godot 4.2+). This is separate from the [GUT](../gut/) addon plugin.

## Requirements

- `godot` or `godot4` on `PATH` (manifest `requires` checks `godot`)
- Godot **4.2+** with the built-in project test runner
- A Godot project with `project.godot` in the tree

## Discovery vs GUT

Both `godot4` and `gut` match `project.godot`. This plugin uses **priority 116** (GUT is 115), so `teez discover` prefers `godot4` when both are available. Pin a runner explicitly when needed:

```lua
plugins = { "godot4" }  -- built-in tests
-- or
plugins = { "gut" }     -- GUT addon
```

## Test discovery

`teez list` discovers:

- `**/*_test.gd`
- `**/*_test.tscn`
- `**/test/**/*.gd`
- `**/test/**/*.tscn`

Override with `runners.godot4.include` / `runners.godot4.exclude`.

## Usage

```bash
teez discover /path/to/godot-project
teez list /path/to/godot-project
teez run /path/to/godot-project --simple
```

In `teez.config.lua`:

```lua
return {
  plugins_dir = "/path/to/teez-plugins/godot4",
  plugins = { "godot4" },
  runners = {
    godot4 = {
      command = "godot4",
      args = { "--verbose" },
    },
  },
}
```

## Run command

Default (Godot 4.2+ built-in editor tests):

```text
godot4 --headless --path <project> --test
```

When specific targets are selected, the plugin passes:

- `--unit-test-file=res://...` for `*_test.gd` scripts
- `--scene res://...` for test scenes under `test/` or `*_test.tscn`

Alternative script-based mode (custom runner script):

```lua
runners = {
  godot4 = {
    script = "res://addons/my_test_runner/run.gd",
  },
}
```

Which runs:

```text
godot4 --headless --path <project> -s res://addons/my_test_runner/run.gd
```

## Runner options

| Key | Description |
|-----|-------------|
| `command` | Godot binary (`godot4` auto-detected when available) |
| `args` | Extra Godot CLI flags (after `--headless --path`) |
| `script` | Use `-s <script>` instead of `--test` |
| `test_args` | Extra flags after `--test` / script |
| `test_file_flag` | Flag for a single GDScript test file (default `--unit-test-file`) |
| `scene_flag` | Flag for scene tests (default `--scene`) |
| `test_name_flag` | Name filter flag (default `--unit-test-filter`) |
| `test_pattern_flag` | Pattern filter flag (default `--unit-test-filter`) |
| `include` / `exclude` | Glob patterns for `teez list` discovery |
| `coverage` | Godot coverage settings (see below) |

CLI filters map to Godot test filters:

- `-n` / name filter → `--unit-test-filter=<name>`
- pattern filter → `--unit-test-filter=<pattern>`

## Coverage

When your Godot build supports it, enable coverage via `runners.godot4.coverage`:

```lua
runners = {
  godot4 = {
    coverage = {
      path = "coverage/godot",
      report = "coverage/godot/coverage.json",
      reporter = "json",
      min_line_rate = 0.8,
      packages = { "res://scripts" },
    },
  },
}
```

Then run:

```bash
teez run . --with-coverage
```

Coverage flags are injected as `--coverage`, `--coverage-path=...`, and optional `--coverage-package=...`.

## Output parsing

`parse_line` maps Godot built-in test stdout such as:

- `test_addition PASSED (0.001s)`
- `test_subtraction FAILED (0.002s)`
- `PASSED: test_name` / `FAILED: test_name`
- `res://test/unit/example_test.gd` (suite start)

Unrecognized lines are emitted as `output` events.
