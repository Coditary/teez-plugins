# teez clojure runner plugin

Clojure [`clojure.test`](https://clojure.github.io/clojure.test/) adapter for teez. Discovers projects with `deps.edn` or `project.clj`, runs tests via the Clojure CLI (`clojure -M:test` / `clojure -X:test`), and optionally integrates with [Kaocha](https://github.com/lambdaisland/kaocha) or [cloverage](https://github.com/cloverage/cloverage).

## Install via ReqPack

```bash
rqp install teez clojure
```

Installs manifest + Lua into `~/.local/share/teez/plugins/`.

## Features

- `run` / `list` via `clojure -M:test` (default) or `clojure -X:test`
- Kaocha support when `runners.clojure.tool = "kaocha"`
- Test discovery via `clojure -M:test -e …`, `kaocha --list`, or file glob fallback
- Parses `clojure.test` output (`Testing …`, `FAIL in`, `ERROR in`, `PASS in`)
- Coverage via cloverage when `runners.clojure.coverage.tool = "cloverage"`
- Runner overrides from `teez.config.lua`

## CLI commands

| teez action | Clojure command |
|-------------|-----------------|
| `teez run` | `clojure -M:test` (or `-X:test`, Kaocha args after `--`) |
| `teez list` | `clojure -M:test -e …` to enumerate `namespace/var` tests; Kaocha uses `--list` |
| `teez run --with-coverage` | `clojure -M:coverage --lcov --output …` when coverage tool is `cloverage` |

## Project setup

### deps.edn (clojure.test)

```clojure
{:paths ["src" "test"]
 :aliases
 {:test {:extra-paths ["test"]
         :exec-fn clojure.test/run-tests
         :exec-args {:namespaces '[my.app-test]}}}}
```

For `-M` instead of `-X`:

```clojure
:test {:extra-paths ["test"]
       :main-opts ["-e" "(require 'my.app-test) (clojure.test/run-tests 'my.app-test)"]}
```

### deps.edn (Kaocha)

```clojure
:test {:extra-paths ["test"]
       :extra-deps {lambdaisland/kaocha {:mvn/version "1.91.1392"}}
       :main-opts ["-m" "kaocha.runner/-main"]}
```

### deps.edn (cloverage)

```clojure
:coverage {:extra-deps {cloverage/cloverage {:mvn/version "1.2.4"}}
           :main-opts ["-m" "cloverage.coverage"
                       "-n" "my.app"
                       "-p" "src" "test"]}
```

## Project override

```lua
return {
    runners = {
        clojure = {
            alias = "test",       -- deps.edn alias (default: test)
            mode = "M",           -- M (-M:alias) or X (-X:alias)
            tool = "kaocha",      -- omit for plain clojure.test
            pattern = "unit",     -- kaocha --focus or namespace filter
            args = { "--reporter", "kaocha.report/dots" },
            coverage = {
                tool = "cloverage",
                alias = "coverage",
                reports_directory = "target/coverage",
                report = "target/coverage/lcov.info",
            },
        },
    },
}
```

Use `command` to override the executable:

```lua
runners = {
    clojure = {
        command = "/usr/bin/clojure",
    },
}
```

For a standalone Kaocha binary instead of the deps alias:

```lua
runners = {
    clojure = {
        tool = "kaocha",
        kaocha_direct = true,
        kaocha_command = "kaocha",
    },
}
```

## Test IDs

- Eval / Kaocha listing: `my.app.core-test/my-function-test` (`namespace/var`)
- File fallback: relative paths such as `test/my_app_test.clj`

## Notes

- Requires the `clojure` executable on `PATH` (`requires: ["clojure"]` in the manifest).
- Priority `115` sits above Deno (`114`) and pytest defaults so Clojure project anchors win when present.
- Default `clojure.test` output only reports failures explicitly; passes are inferred from the summary unless a verbose/Kaocha reporter prints them.
- `--with-coverage` is enabled only when `runners.clojure.coverage.tool = "cloverage"`; configure a matching `:coverage` alias in `deps.edn`.
