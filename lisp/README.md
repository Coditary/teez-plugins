# teez Lisp runner (FiveAM / ASDF)

teez runner plugin for Common Lisp projects that run tests via ASDF `test-op` and [FiveAM](https://github.com/sionescu/fiveam).

## Discovery

Matches projects containing `*.asd` files (`glob_anchors`).

Test targets are ASDF system names discovered from `defsystem` forms that declare a `test-op` (or `:test-system`).

## Requirements

Default Lisp implementation: **SBCL** (`sbcl` on `PATH`). The manifest `requires` field checks for `sbcl`.

For [Roswell](https://github.com/roswell/roswell)-only setups, set `runners.lisp.command = "ros"` and remove or override `requires` in a project-local manifest copy.

## Configuration

```lua
return {
  plugins_dir = "/path/to/teez-plugins/lisp",
  plugins = { "lisp" },
  runners = {
    ["lisp"] = {
      -- sbcl (default) or ros
      command = "sbcl",

      -- run only these systems (default: auto-discover from *.asd)
      systems = { "my-system" },

      -- extra ASDF search paths
      load_path = { "src" },

      -- extra CLI args passed to sbcl/ros
      args = {},

      -- SBCL coverage via sb-cover (requires build_coverage_run / --with-coverage)
      coverage = false,
      coverage_report = "coverage/sb-cover.lisp",
    },
  },
}
```

## Commands

| teez command | behavior |
|--------------|----------|
| `teez list .` | ASDF system names with `test-op` |
| `teez run .` | `(asdf:test-system :system)` for each discovered system |
| `teez run . --with-coverage` | SBCL `sb-cover` when `runners.lisp.coverage = true` |

## ASDF setup

Your `.asd` file should wire FiveAM into `test-op`, for example:

```lisp
(defsystem my-system/tests
  :depends-on (my-system fiveam)
  :components ((:file "tests"))
  :perform (test-op (o c)
             (symbol-call :fiveam :run! 'my-system.tests)))

(defsystem my-system
  :depends-on (...)
  :in-order-to ((test-op (test-component "my-system/tests"))))
```

Or use `:test-system "my-system/tests"` on ASDF 3.3+.

## Filters

CLI filters (`-n`, `-t`, `-f`) apply to discovered system IDs in `list` and to explicit ID filters during `run`.

## Files

| File | Purpose |
|------|---------|
| `teez-plugin-lisp.json` | Manifest (`name`: `lisp`, `priority`: 115) |
| `teez-plugin-lisp.lua` | Runner implementation |
