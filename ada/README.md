# teez Ada AUnit Runner

teez runner plugin for [Ada AUnit](https://github.com/AdaCore/aunit) projects built with **gprbuild** or managed by **Alire** (`alr`).

## Discovery

Matches projects that contain a `*.gpr` file (via `glob_anchors`).

| Manifest field | Value |
|----------------|-------|
| `name` | `ada` |
| `priority` | `115` |
| `include` | `**/*-tests.adb`, `**/tests/**` |

### Tool requirements

Projects typically use **either** `gprbuild` (GNAT toolchain) **or** `alr` (Alire). teez manifest `requires` checks that **all** listed tools exist, so this plugin does not set `requires` in the manifest. Tool availability is checked at runtime instead.

Install one of:

- [GNAT](https://www.adacore.com/gnat) / `gprbuild`
- [Alire](https://alire.rocks/) / `alr`

## Setup

Point your project config at this plugin directory:

```lua
return {
    plugins_dir = "/path/to/teez-plugins/ada",
    plugins = { "ada" },
    runners = {
        ada = {
            -- Optional: force a backend
            -- use_alr = true,
            -- use_gprbuild = true,

            project = "tests/tests.gpr",
            test_executable = "bin/run_tests",

            -- Extra CLI args forwarded to alr test / the test runner
            args = {},

            -- gprbuild-only extras
            gprbuild_args = { "-j0" },
            run_args = {},
            run_dir = ".",

            -- Coverage via gnatcov (see below)
            -- coverage = true,
        },
    },
}
```

## Commands

### List (`teez list`)

Discovery order:

1. `alr test --list` when `alr.toml` is present and `alr` supports listing
2. Test executables declared in `.gpr` files or found under `bin/` / `obj/`
3. Test procedure IDs parsed from `*-tests.adb` and `tests/**` sources

### Run (`teez run`)

| Backend | Behavior |
|---------|----------|
| **Alire** | `alr test -q` (+ optional `args` / CLI filters) |
| **gprbuild** | `gprbuild -P <project> <executable> && <executable>` |

Alire is selected when `alr.toml` exists and `alr` is on `PATH`, unless `use_gprbuild = true` is set.

CLI name filters (`-n`) are forwarded as repeated `--filter <pattern>` arguments when supported by the underlying runner.

## AUnit output

`parse_line` understands common AUnit text reporter formats:

```
Test Case: Suite.Procedure_Name
  Status: PASSED
```

```
PASSED: Suite.Procedure_Name
FAILED: Suite.Procedure_Name
```

```
Running Test Suite.Procedure_Name ... PASSED
```

```
ok 1 - procedure_name
not ok 2 - procedure_name
```

## Coverage (`--with-coverage`)

Enable in config:

```lua
runners = {
    ada = {
        coverage = true,
        coverage_dir = "coverage",
        min_line_rate = 0.8,
        gnatcov_instrument_args = {},
        gnatcov_export_args = {},
    },
},
```

Requires `gnatcov` on `PATH`. The plugin:

1. Runs `gnatcov instrument` on the project `.gpr`
2. Builds and runs the test suite with `GNATCOV_TRACE_FILE` set
3. Exports LCOV via `gnatcov export`

## Verify

```bash
teez discover . --json
teez list .
teez run . --simple
teez run . --with-coverage   # when coverage = true
```
