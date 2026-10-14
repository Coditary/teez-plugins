# teez Stan / CmdStan runner

teez runner plugin for Stan statistical model tests via CmdStan.

## Discovery

Matches projects containing `*.stan` files when `stanc` is on `PATH` (CmdStan `bin/` directory).

| Manifest field | Value |
|----------------|-------|
| `glob_anchors` | `*.stan` |
| `include` | `**/tests/**`, `**/*_test.stan` |
| `requires` | `stanc` |
| `priority` | `115` |

## Project layout

Typical layout:

```
my-stan-project/
├── teez.config.lua
├── models/
├── tests/
│   ├── bernoulli_test.stan
│   └── regression_test.stan
└── python/
    └── run_tests.py
```

Test models are discovered under `tests/` or as `*_test.stan` anywhere in the tree.

## Configuration

Add the plugin directory in `teez.config.lua`:

```lua
return {
    plugins_dir = "/path/to/teez-plugins/stan",
    plugins = { "stan" },
    runners = {
        stan = {
            -- "python" (default) or "cmdstan"
            harness = "python",

            -- CmdStan install root; adds bin/stanc and sets CMDSTAN
            cmdstan_path = "/opt/cmdstan-2.35.0",

            -- Override stanc binary (optional)
            -- stanc = "/opt/cmdstan/bin/stanc",

            -- Python harness settings
            python = "python3",
            test_script = "python/run_tests.py", -- default: python/run_tests.py, then run_tests.py

            -- Extra args passed before test file paths
            args = { "--verbose" },

            -- CmdStan harness: stanc flags for compile-only validation
            stanc_args = { "--warn=error" },

            -- Optional env vars for the child process
            env = {
                STAN_NUM_THREADS = "4",
            },

            -- Override manifest include/exclude
            -- include = { "**/tests/**", "**/*_test.stan" },
            -- exclude = { "**/experimental/**" },
        },
    },
}
```

## Harness modes

### Python harness (default)

Runs `python/run_tests.py` (or `run_tests.py`) with discovered `.stan` test paths appended as arguments.

Your script should print teez-compatible lines on stdout:

```
START tests/bernoulli_test.stan
PASS tests/bernoulli_test.stan
FAIL tests/bad_test.stan: divergent transitions exceeded threshold
SKIP tests/slow_test.stan
```

Pytest-style lines are also recognized: `tests/foo.stan PASSED` / `FAILED`.

### CmdStan harness

Set `harness = "cmdstan"` to compile each test model with `stanc` (`--warn=error` by default). Useful when you only need compilation checks without a Python test driver.

## Commands

```bash
teez discover .
teez list .
teez run . --simple
teez run . -n bernoulli
```

## Coverage

Code coverage is not supported for Stan models. Use your `run_tests.py` harness to emit model validation metrics (e.g. R-hat, ESS, divergence counts) as `output` events or structured logs; teez will surface unparsed lines as test output.

## Requirements

- CmdStan with `stanc` on `PATH`, or `runners.stan.cmdstan_path` pointing at a CmdStan install
- Python harness: `python3` and a project `run_tests.py` (often using `cmdstanpy`)
