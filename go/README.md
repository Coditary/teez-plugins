# teez Go test runner plugin

Go adapter for teez. Discovers modules with `go.mod` and runs tests via `go test`.

## Install via ReqPack

```bash
rqp install teez go
```

Installs manifest + Lua into `~/.local/share/teez/plugins/`.

## Project override

```lua
return {
    runners = {
        go = {
            pattern = "^TestUnit",
            include = { "**/*_test.go" },
            exclude = { "**/vendor/**" },
            args = { "-count=1", "-race" },
        },
    },
}
```

### Runner config keys

| Key | Description |
|-----|-------------|
| `args` | Extra flags appended to `go test` (after `-v` / coverage flags) |
| `pattern` | Passed as `-run` regex to match test names |
| `include` | Glob patterns for `*_test.go` files; matching files map to package paths |
| `exclude` | Glob patterns excluded from the include set |

When `include` is not set in config, the plugin runs `./...` from the module root (or `./<target>/...` for subdirectory targets).

## Test IDs

Listed tests use `package/path::TestName` (for example `./internal/foo::TestBar` or `.::TestMainSuite`). Subtests appear as `TestName/subtest`.

## Coverage

With `teez run --with-coverage`, the plugin runs:

```bash
go test -coverprofile=coverage.out -covermode=atomic ...
```

The profile path is reported as `coverage.out` relative to the module root.
