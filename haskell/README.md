# teez Haskell runner (Tasty)

teez runner plugin for Haskell projects using **Tasty** (and HUnit) via `cabal test` or `stack test`.

## Discovery

Matches projects containing:

- `*.cabal`, or
- `package.yaml` (hpack / Stack)

Default test file globs:

- `**/test/**/*.hs`
- `**/tests/**/*.hs`
- `**/*Test.hs`
- `**/*Spec.hs`

## Tool selection

The plugin picks the build tool automatically:

1. `runners.haskell.tool = "stack"` or `"cabal"` when set in config
2. otherwise `stack.yaml` / `stack.yaml.lock` present and `stack` on `PATH` → `stack test`
3. otherwise `cabal` on `PATH` → `cabal test`
4. otherwise `stack` on `PATH` as fallback

The manifest declares `"requires": ["cabal"]` for discovery. At run time the plugin still auto-selects **stack** when `stack.yaml` is present (unless `runners.haskell.tool = "cabal"`). Stack-only environments can pin the plugin in config and drop `requires` locally if needed.

## Project setup

Point teez at your package root (where the `.cabal` or `package.yaml` lives):

```lua
-- teez.config.lua
return {
  plugins_dir = "/path/to/teez-plugins/haskell",
  plugins = { "haskell" },
  runners = {
    haskell = {
      -- tool = "stack",      -- force stack or cabal
      -- pattern = "reverse", -- Tasty --pattern filter
      -- test = "pkg:test:unit", -- cabal test target
      -- args = { "all" },    -- extra cabal/stack args
      -- test_options = { "--timeout=30s" },
      -- include / exclude override manifest globs
    },
  },
}
```

## Commands

| teez | Backend |
|------|---------|
| `teez list .` | `cabal test --test-show-details=direct --test-options '--list-tests …'` or `stack test --test-arguments '… --list-tests'`; falls back to test file paths |
| `teez run .` | `cabal test` / `stack test` with `--color=never` and optional Tasty pattern |

Test IDs come from Tasty `--list-tests` output (preferred) or discovered `.hs` paths.

## Output parsing

`parse_line` understands Tasty / HUnit style lines:

- `Some/Group/test: OK` → pass
- `Some/Group/test: FAIL` → fail
- `Some/Group/test: SKIP` → skip
- `Test suite …: PASS|FAIL` → suite-level result

Unrecognized lines are emitted as `output` events.

## Coverage

Enable with `teez run . --with-coverage`. Configure via `runners.haskell.coverage`:

### HPC (default)

```lua
runners = {
  haskell = {
    coverage = {
      tool = "hpc",
      hpcdir = "dist/hpc/vanilla/tix",
      markup_dir = "coverage/hpc",
      report = "coverage/hpc.summary.txt",
      output = "coverage/teez.msgpack",
      reporter = "msgpack",
      mix = false,                 -- set true to hpc markup --union all
      configure_args = { "--enable-coverage" },
      min_line_rate = 0.8,
    },
  },
}
```

Runs tests with coverage, then `hpc markup` + `hpc report`.

### HIE coverage

```lua
runners = {
  haskell = {
    coverage = {
      tool = "hie",
      report = "coverage/lcov.info",
      output = "coverage/teez.msgpack",
      reporter = "lcov",
      collect_command = "hie-coverage",
      collect_args = { "report", "--lcov", "coverage/lcov.info" },
    },
  },
}
```

Requires `hie-coverage` (or override `collect_command`) on `PATH`.

## Quick check

```bash
teez discover . --json
teez list .
teez run . --simple
teez run . --with-coverage
```
