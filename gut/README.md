# teez GUT runner

[teez](https://github.com/Coditary/teez-core) runner plugin for [GUT](https://github.com/bitwes/Gut) (Godot Unit Test) projects.

## Requirements

- `godot` or `godot4` on `PATH` (manifest `requires` checks `godot`)
- GUT installed at `addons/gut/` (default entry script: `addons/gut/gut_cmdln.gd`)
- A Godot project with `project.godot` in the tree

## Discovery

Matches Godot projects via the `project.godot` anchor.

Test files are discovered with:

- `**/*_test.gd`
- `**/test/**/*.gd`

Override with `runners.gut.include` / `runners.gut.exclude`.

## Usage

Point teez at your Godot project (or a subdirectory):

```bash
teez discover /path/to/godot-project
teez list /path/to/godot-project
teez run /path/to/godot-project --simple
```

In `teez.config.lua`:

```lua
return {
  plugins_dir = "/path/to/teez-plugins/gut",
  plugins = { "gut" },
  runners = {
    gut = {
      -- Use godot4 when only that binary is installed
      command = "godot4",
      test_dir = "res://test",
      gut_args = { "-glog=2" },
    },
  },
}
```

## Runner options

| Key | Description |
|-----|-------------|
| `command` | Godot binary (`godot4` auto-detected when `godot` is absent) |
| `args` | Extra Godot CLI flags (before `-s`) |
| `gut_script` | Path to GUT cmdline script (default `addons/gut/gut_cmdln.gd`) |
| `gut_args` | Extra GUT flags (`-gdir`, `-gselect`, `-glog`, …) |
| `gut_dir` | Fixed GUT directory (`-gdir=...`) |
| `test_dir` | Default test directory when no files are targeted (default `res://test`) |
| `gut_prefix` | GUT class prefix (`-gprefix`) |
| `gut_suffix` | GUT file suffix (`-gsuffix`, default `_test.gd`) |
| `gut_include_subdirs` | Pass `-ginclude_subdirs` |
| `include` / `exclude` | Glob patterns for `teez list` discovery |
| `coverage` | Godot coverage settings (see below) |

CLI filters map to GUT as:

- `-n` / name filter → `-gselect`
- pattern filter → `-gunit_test_name`

## Run command

The plugin runs GUT headless:

```text
godot --headless -s addons/gut/gut_cmdln.gd -gexit ...
```

When multiple `*_test.gd` files are selected, each file is passed via `-gtest=res://...`.

## Coverage

Enable Godot’s built-in coverage collector via `runners.gut.coverage`:

```lua
runners = {
  gut = {
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

Coverage flags are injected as `--coverage` and `--coverage-path=...` (and optional `--coverage-package=...`).

## Output parsing

`parse_line` maps GUT stdout lines such as `[Passed]: test_name` and `[Failed]: test_name` to teez events. Unrecognized lines are emitted as `output` events.
