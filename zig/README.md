# teez zig runner plugin

Zig adapter for teez. Discovers projects with `build.zig` or `build.zig.zon` and runs `std.testing` via `zig build test` or `zig test`.

## Install

Copy this directory into your project `plugins/` folder, or install alongside other teez plugins:

```bash
cp -r zig/ ~/.local/share/teez/plugins/
```

Requires `zig` on `PATH`.

## Features

- `run` via `zig build test` when `build.zig` exists, otherwise `zig test`
- `list` via `zig test --list-tests` per `.zig` file, with file-path fallback
- Pass / fail / skip parsing from Zig test output (`Test [n/m] name... OK|FAILED|SKIP`)
- Optional duration extraction from `(12.34 ns)` / `(1.2 ms)` suffixes
- Coverage via `teez run . --with-coverage` when `zig test --coverage` is supported
- Runner overrides from `teez.config.lua`

## Project override

```lua
return {
    plugins_dir = "plugins",
    plugins = { "zig" },
    runners = {
        zig = {
            -- Force zig test instead of zig build test
            use_build = false,
            -- Maps to --test-filter
            pattern = "my_test",
            args = { "-freference-trace" },
            coverage = {
                reports_directory = "zig-out/coverage",
                report = "zig-out/coverage/lcov.info",
                -- For build-system projects (default: -Dcoverage=true)
                build_arg = "-Dcoverage=true",
            },
        },
    },
}
```

## Test IDs

- File mode: `src/main.zig > test.add`
- Build mode without file context: `test.add` (qualified test name from Zig)

## Notes

- `teez list` uses `zig test --list-tests` on discovered `**/*.zig` files. If listing fails (compile errors), teez falls back to file paths.
- For monorepos, set `runners.zig.include` / `exclude` to scope discovery.
- `zig build test` forwards `--test-filter` after `--` to the underlying test executables.
