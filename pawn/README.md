# teez Pawn / PawnUnit runner

teez runner plugin for [PawnUnit](https://github.com/Zeex/pawnunit) test scripts in SA-MP / open.mp style projects.

## Discovery

Matches when the project contains `pawn.json` or `pawno.cfg`.

Test scripts are discovered from:

- `**/tests/**/*.pwn`
- `**/*_test.pwn`

## Requirements

The compiler or test tool is **not** pinned in the manifest. Configure it via `runners.pawn.command` (default: `pawncc`) or use `sampctl` mode.

## Configuration

```lua
return {
  plugins_dir = "/path/to/teez-plugins/pawn",
  plugins = { "pawn" },
  runners = {
    pawn = {
      -- Compiler on PATH (default: pawncc)
      command = "pawncc",

      -- Extra pawncc flags
      args = { "-d3", "-;+", "-(+", "-\\+", "-Z+" },
      include_dirs = { "include", "tests" },
      defines = { "UNIT_TEST" },
      output_dir = "tests/amx",

      -- After compile, run tests with a server or harness binary
      runner = "omp-server",
      runner_args = { "--config", "server.cfg" },

      -- Or run everything through sampctl
      -- sampctl = true,
      -- mode = "sampctl",

      -- Or delegate to a project wrapper script
      -- test_command = "./scripts/run-pawnunit.sh",
      -- test_args = {},

      -- Coverage for `teez run --with-coverage`
      coverage = true,
      -- coverage = {
      --   collect = { command = "gcovr", args = { "--txt" } },
      --   report = "coverage/lcov.info",
      --   reporter = "lcov",
      --   output = "coverage/teez.msgpack",
      --   min_line_rate = 0.8,
      -- },
    },
  },
}
```

## Run modes

| Mode | When | Command |
|------|------|---------|
| `sampctl` | `sampctl = true` or `mode = "sampctl"` | `sampctl test` |
| `pawncc + runner` | `runner` is set | `pawncc … && <runner> …` |
| `pawncc` | default | `pawncc` on discovered test files |
| `wrapper` | `test_command` is set | custom command |

If `pawno.cfg` exists and `include_dirs` is omitted, `-i` paths are read from that file.

## Output parsing

`parse_line` understands PawnUnit style output:

```
PASS: test_Addition
FAIL: test_Division: expected 2, got 0
[+] test_Addition
[-] test_Division: expected 2, got 0
SKIP: test_Ignored
```

## Usage

```bash
teez discover .
teez list .
teez run . --simple
teez run . --with-coverage   # when runners.pawn.coverage is set
```
