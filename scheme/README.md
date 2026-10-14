# teez Scheme (SRFI-64) Runner

teez runner plugin for [SRFI-64](https://srfi.schemers.org/srfi-64/srfi-64.html) Scheme tests.

## Discovery

Matches projects containing `*.scm` or `*.sls` files. Test files are collected from:

- `**/test/**`
- `**/*-test.scm`
- `**/*_test.scm`

## Requirements

A Scheme implementation must be available on `PATH`, unless `runners.scheme.command` is set.

Auto-detection order:

1. `guile`
2. `chicken`
3. `scheme` (Chibi or other `scheme` binary)

> **Racket fallback:** Racket is not SRFI-64 compatible out of the box. If you must use Racket, set `runners.scheme.command = "racket"` and provide a custom `test_runner` that loads your adapter. Prefer Guile or Chicken for native SRFI-64 support.

## Project setup

Add a `test-runner.scm` in the project root (or set `runners.scheme.test_runner`):

```scheme
#!/usr/bin/env guile
!#

(use-modules (srfi srfi-64))

(define (teez-report result)
  (let ((name (test-result-test-name result)))
    (case (test-result-kind result)
      ((pass) (display (string-append "PASS: " name "\n")))
      ((fail)
       (display (string-append "FAIL: " name ": "
                               (or (test-result-reason result) "failed") "\n")))
      ((skip) (display (string-append "SKIP: " name "\n")))
      (else #f))))

(define runner
  (test-runner-on-test-end (test-runner-null) teez-report))

(test-with-runner runner
  (lambda ()
    (for-each load (cdr (command-line)))))

(test-runner? runner)
```

Run a single test file:

```bash
guile -l test-runner.scm tests/foo-test.scm
```

Chicken uses `-script` instead of `-l`; the plugin selects the right invocation for the resolved command.

## Configuration

```lua
return {
  plugins_dir = "/path/to/teez-plugins/scheme",
  plugins = { "scheme" },
  runners = {
    scheme = {
      -- command = "guile",      -- override auto-detection
      -- test_runner = "test-runner.scm",
      -- args = { "--no-auto-compile" },
      -- include = { "**/test/**", "**/*-test.scm" },
      -- exclude = { "**/vendor/**" },
      coverage = {
        reporter = "lcov",
        report = "coverage/lcov.info",
        output = "coverage/teez.msgpack",
        collect = {
          command = "gcovr",
          args = { "--txt-metric", "line" },
        },
        env = {
          CHICKEN_COVERAGE = "1",
        },
      },
    },
  },
}
```

When `runners.scheme.coverage` is set, `teez run --with-coverage` uses `build_coverage_run`. Coverage collection is implementation-specific; configure `coverage.collect` and `coverage.env` for your toolchain (for example Chicken's `CHICKEN_COVERAGE`).

## Output format

`parse_line` recognizes SRFI-64 style lines emitted by `test-runner.scm`:

| Line | Event |
|------|-------|
| `PASS: test-name` | pass |
| `FAIL: test-name: reason` | fail |
| `SKIP: test-name` | skip |
| `START: test-name` | start |
| `Test passed: test-name` | pass |
| `Test failed: test-name` | fail |
| `Unexpected failure: test-name` | fail |

Summary lines (`# of unexpected failures`, `;;;; ...`) are reported as `output`.

## Usage

```bash
teez discover .
teez list .
teez run . --simple
teez run . --with-coverage   # when runners.scheme.coverage is configured
```
