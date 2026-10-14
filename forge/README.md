# teez Foundry Forge Runner

teez runner plugin for [Foundry Forge](https://book.getfoundry.sh/) Solidity projects.

## Discovery

Matches projects with `foundry.toml` on disk and `forge` available on `PATH`.

| Manifest field | Value |
|----------------|-------|
| `name` | `forge` |
| `priority` | `115` |
| `anchors` | `foundry.toml` |
| `requires` | `forge` |
| `include` | `**/test/**/*.sol`, `**/src/**` |

## Commands

| teez action | Forge command |
|-------------|---------------|
| `teez list` | `forge test --list` |
| `teez run` | `forge test -vvv` |
| `teez run --with-coverage` | `forge coverage --report lcov` |

## Test IDs

IDs use the form `ContractName::testFunction`, parsed from `forge test --list` tree output and matched against `forge test -vvv` `[PASS]` / `[FAIL]` lines using the active contract from `Running N tests for <file>:<Contract>`.

## Configuration

```lua
return {
  plugins_dir = "/path/to/teez-plugins/forge",
  plugins = { "forge" },
  runners = {
    ["forge"] = {
      args = { "--fork-url", "http://127.0.0.1:8545" },
      include = { "**/test/**/*.sol" },
      exclude = { "**/script/**" },
    },
  },
}
```

The `runners.forge` key must match the manifest `name` exactly.

### Runner options

| Key | Description |
|-----|-------------|
| `args` | Extra arguments appended to `forge test`, `forge test --list`, and `forge coverage` |
| `include` | Glob patterns; only listed tests from matching paths (via `filter.glob_match`) |
| `exclude` | Glob patterns excluded after `include` |

CLI filters (`-f`, `-n`) are passed as `--match-test <pattern>` when set.

## Coverage

`build_coverage_run` runs `forge coverage --report lcov` and reports `lcov.info` from the project root.

## Usage

```bash
teez discover .
teez list .
teez run . --simple
teez run . --with-coverage
```
