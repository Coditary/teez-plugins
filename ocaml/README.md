# teez OCaml runner plugin

OCaml / Alcotest adapter for teez. Discovers projects with `dune-project` and runs tests via `dune test` (alias for `dune runtest`).

## Install

Copy or symlink this directory into your teez plugins path, or point `plugins_dir` at `teez-plugins/ocaml`:

```lua
return {
    plugins_dir = "/path/to/teez-plugins/ocaml",
    plugins = { "ocaml" },
}
```

Requires `dune` on `PATH`.

## Usage

```bash
teez discover .
teez list .
teez run . --simple
teez run . --with-coverage
```

## Project config

```lua
return {
    runners = {
        ocaml = {
            -- dune binary (default: "dune")
            -- command = "dune",

            -- "test" or "runtest" (default: "test")
            -- subcommand = "test",

            -- always re-run tests (recommended for CI / coverage)
            force = true,

            args = { "--verbose" },

            coverage = {
                instrument = "bisect_ppx",
                report = "coverage/cobertura.xml",
                output = "coverage/teez.msgpack",
                reporter = "cobertura",
                collect_command = "bisect-ppx-report",
                collect_args = { "cobertura", "coverage/cobertura.xml" },
                -- coverage_path = "_build/default",
                min_line_rate = 0.8,
            },
        },
    },
}
```

Libraries and executables must declare `(instrumentation (backend bisect_ppx))` in their `dune` files for coverage runs.

## Test IDs

`teez list` combines:

- `dune describe targets` / `dune describe workspace` entries (`runtest/<name>`, `@runtest-*` aliases)
- file-based IDs from `**/*_test.ml`, `**/*_test.mli`, and `**/test/**`

During runs, Alcotest lines are mapped to `Suite::index::case` (for example `Greeting::0::can greet Tom`).

## Parsing

`parse_line` handles Alcotest result lines (`[OK]`, `[FAIL]`, `[SKIP]`, `[ERROR]`), suite headers (`Testing '…'`), and common dune failure output.
