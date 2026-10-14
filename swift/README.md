# teez Swift / XCTest Runner

teez runner plugin for [Swift Package Manager](https://www.swift.org/documentation/package-manager/) projects using `swift test` and XCTest.

## Requirements

- `swift` on `PATH` (Swift Toolchain)
- A `Package.swift` at the project root

## Discovery

Matches Swift packages via the `Package.swift` anchor. Test sources are expected under `Tests/` (see manifest `include`).

## Usage

Point `plugins_dir` at this directory (or copy these files into your project `plugins/` folder):

```lua
return {
    plugins_dir = "/path/to/teez-plugins/swift",
    plugins = { "swift" },
    runners = {
        swift = {
            -- optional extra flags forwarded to `swift test`
            args = {},
        },
    },
}
```

```bash
teez discover .
teez list .
teez run . --simple
teez run . --with-coverage
```

## Commands

| teez | swift |
|------|-------|
| `list` | `swift test --list-tests` |
| `run` | `swift test --parallel=false -v` |
| `--with-coverage` | `swift test --enable-code-coverage --parallel=false -v` |

CLI name filters (`-n`) map to `swift test --filter`.

## Test IDs

`swift test --list-tests` IDs are used as-is, e.g. `MyPackageTests.MyTests/testExample`.

Verbose run output (`Test Case '-[Class method]' passed/failed`) is normalized to the same `Class/method` form.

## Coverage

Coverage runs enable instrumentation via `--enable-code-coverage`. To export an LCOV report, set the test binary path in config (platform-specific):

```lua
runners = {
    swift = {
        profdata = ".build/debug/codecov/default.profdata",
        coverage_object = ".build/debug/MyPackagePackageTests.xctest/Contents/MacOS/MyPackagePackageTests",
        coverage_report = "coverage/lcov.info",
    },
},
```

On Linux, adjust `coverage_object` to your `.xctest` executable path under `.build/debug/`.

## Files

| File | Purpose |
|------|---------|
| `teez-plugin-swift.json` | Manifest (anchors, requires, priority) |
| `teez-plugin-swift.lua` | `list`, `build_command`, `parse_line`, `build_coverage_run` |
