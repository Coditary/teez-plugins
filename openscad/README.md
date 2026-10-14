# teez OpenSCAD runner

teez runner plugin for [OpenSCAD](https://openscad.org/) projects, with optional [BOSL2](https://github.com/BOSL2/BOSL2) test-runner integration.

## Discovery

Matches projects containing `*.scad` files. Test files are discovered from:

- `**/tests/**` — any `.scad` file under a `tests/` directory
- `**/*_test.scad` — files named `*_test.scad`

Requires `openscad` on `PATH`.

## Usage

Point teez at your OpenSCAD project (or add this plugin directory via `plugins_dir`):

```bash
teez discover .
teez list .
teez run . --simple
```

Filter tests with standard teez CLI filters (`-n`, `-t`, `-f`).

## Run modes

### Default (compile validation)

Each test file is rendered to `/dev/null`:

```bash
openscad -o /dev/null path/to/test.scad
```

When multiple tests are selected, the plugin runs them in sequence and emits `PASS` / `FAIL` lines for reporting.

### BOSL2 test runner

Use a project-specific BOSL2 test script via `runners.openscad.command`:

```lua
return {
  plugins_dir = "/path/to/teez-plugins/openscad",
  plugins = { "openscad" },
  runners = {
    openscad = {
      command = "openscad",
      args = { "-o", "/dev/null", "tests/run_tests.scad" },
      append_target = false,
    },
  },
}
```

| Key | Description |
|-----|-------------|
| `command` | Executable for BOSL2 (or custom) test runner |
| `args` | Arguments passed before the target path |
| `append_target` | Append `target_path` to args (default: `true`) |
| `cwd` | Working directory for the child process |
| `env` | Extra environment variables |
| `include` / `exclude` | Override manifest glob patterns for `list` |

BOSL2 test output should use `PASS <id>` and `FAIL <id>` (optional `- message`) lines; the plugin maps these to teez events.

## Coverage

Not supported (`--with-coverage` N/A).
