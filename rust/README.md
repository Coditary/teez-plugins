# teez Rust runner plugin

Rust [`cargo test`](https://doc.rust-lang.org/cargo/commands/cargo-test.html) adapter for teez. Discovers projects with `Cargo.toml`, lists tests via `cargo test -- --list` (after a compile-only `cargo test --no-run`), and runs tests with `cargo test -- --nocapture`.

## Install

Copy or symlink this directory into your teez plugins path, or point `plugins_dir` at `teez-plugins`:

```lua
return {
    plugins_dir = "/path/to/teez-plugins/rust",
    plugins = { "rust" },
}
```

For a flat plugins layout, place `teez-plugin-rust.json` and `teez-plugin-rust.lua` in the same directory and set `plugins_dir` to that folder.

## Features

- Discovery via `Cargo.toml` anchor
- `list` — `cargo test --no-run`, then `cargo test -- --list`; returns test name strings
- `run` — `cargo test -- --nocapture` with optional package, integration target, and name filter
- Parses `test … ok`, `test … FAILED`, `test … ignored`, and `test result:` lines
- Coverage via `cargo llvm-cov` (default) or `cargo tarpaulin` when configured
- Runner overrides from `teez.config.lua`

## CLI mapping

| teez action | cargo command |
|-------------|---------------|
| `teez list` | `cargo test --no-run` then `cargo test -- --list` |
| `teez run` | `cargo test [filter] -- --nocapture` |
| `teez run --with-coverage` | `cargo llvm-cov test …` or `cargo tarpaulin …` |

## Project setup

### Unit and integration tests

```text
my-crate/
├── Cargo.toml
├── src/
│   └── lib.rs          # #[cfg(test)] mod tests { … }
└── tests/
    └── integration.rs  # integration test target
```

### teez.config.lua

```lua
return {
    plugins_dir = "plugins",
    plugins = { "rust" },
    runners = {
        rust = {
            -- Cargo package in a workspace (maps to -p)
            package = "my-crate",

            -- Integration test target (maps to --test)
            test_target = "integration",

            -- Name filter passed to cargo test (substring match, like Go's -run)
            pattern = "my_test",

            -- Extra cargo test flags before the `--` separator
            args = { "--features", "test-utils" },

            -- Override manifest include/exclude globs
            include = { "**/tests/**/*.rs", "**/src/**/test_*.rs" },
            exclude = { "**/benches/**" },

            -- Coverage tool: "llvm-cov" (default) or "tarpaulin"
            coverage_tool = "llvm-cov",
            coverage = {
                tool = "llvm-cov",
                report = "coverage/lcov.info",
                output = "coverage/teez.msgpack",
                reporter = "lcov",
                args = { "--all-features" },
            },
        },
    },
}
```

## Coverage

### cargo-llvm-cov (default)

Install the subcommand:

```bash
cargo install cargo-llvm-cov
```

Configure in `teez.config.lua`:

```lua
runners = {
    rust = {
        coverage_tool = "llvm-cov",
        coverage = {
            report = "coverage/lcov.info",
            reporter = "lcov",
            output = "coverage/teez.msgpack",
            min_line_rate = 0.8,
        },
    },
},
```

`teez run --with-coverage` runs:

```bash
cargo llvm-cov test --lcov --output-path coverage/lcov.info
```

### cargo-tarpaulin

Install:

```bash
cargo install cargo-tarpaulin
```

Configure:

```lua
runners = {
    rust = {
        coverage_tool = "tarpaulin",
        coverage = {
            output_dir = "coverage",
            report = "coverage/lcov.info",
            reporter = "lcov",
            args = { "--all-features" },
        },
    },
},
```

`teez run --with-coverage` runs:

```bash
cargo tarpaulin --out Lcov --output-dir coverage
```

## Runner keys

| Key | Description |
|-----|-------------|
| `args` | Extra arguments to `cargo test` before `--` |
| `pattern` | Test name filter (substring match; teez CLI name filters also apply) |
| `package` | Workspace package (`-p`) |
| `test_target` | Integration test binary (`--test`) |
| `include` | Glob patterns for Rust test sources (listing skips when none match) |
| `exclude` | Glob patterns to exclude from the include set |
| `coverage_tool` | `llvm-cov` or `tarpaulin` |
| `coverage` | Coverage report paths, reporter, `min_line_rate`, and tool-specific `args` |

## Notes

- Test IDs are the names reported by `cargo test -- --list` (e.g. `tests::it_works`, doc tests with file paths).
- Workspace crates: set `runners.rust.package` to the member crate name.
- Integration tests live under `tests/*.rs`; use `test_target` without the `.rs` extension.
- Coverage requires the corresponding cargo subcommand on `PATH`; unsupported `coverage_tool` values disable `build_coverage_run`.
