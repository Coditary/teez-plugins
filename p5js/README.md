# teez p5.js test runner plugin

Adapter for p5.js / Processing.js projects that use **Mocha** or **Jest** style test utilities. Matches projects with `package.json` plus sketch or HTML entry points.

## Install via ReqPack

```bash
rqp install teez p5js
```

Installs manifest + Lua into `~/.local/share/teez/plugins/`.

## Discovery

The runner matches when:

- `package.json` exists, and
- a p5 sketch or HTML entry is present (`**/sketch.js`, `index.html`), or
- the plugin is pinned in `teez.config.lua`

Test files are discovered from:

- `**/*.test.js`
- `**/test/**` (`.js` files)

## Usage

```lua
-- teez.config.lua
return {
    plugins_dir = "/path/to/teez-plugins",
    plugins = { "p5js" },
    runners = {
        p5js = {
            framework = "mocha",   -- or "jest"; auto-detected from package.json
            use_npm = true,        -- run `npm test` instead of `npx mocha` / `npx jest`
            npm_script = "test",
            pattern = "sketch",    -- mocha --grep / jest --testNamePattern
            include = { "**/*.test.js", "**/test/**" },
            exclude = { "**/node_modules/**" },
            args = { "--timeout", "5000" },
            coverage = {
                report = "coverage/lcov.info",
                reporters = { "lcov", "text-summary" },
                min_line_rate = 0.8,
            },
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

## Runner config keys

| Key | Description |
|-----|-------------|
| `framework` | Force `mocha` or `jest` (default: detect from `package.json`) |
| `use_npm` | When `true`, run `npm run <script>` instead of `npx` |
| `npm_script` | npm script name (default: `test`) |
| `pattern` / `grep` | Name filter passed to Mocha `--grep` or Jest `--testNamePattern` |
| `include` | Glob patterns for test file discovery |
| `exclude` | Glob patterns excluded from discovery |
| `args` | Extra CLI args appended to the test command |
| `coverage` | NYC options (see below) |

### `coverage` keys

| Key | Description |
|-----|-------------|
| `report` | NYC output path (default: `coverage/lcov.info`) |
| `reporters` / `reporter` | NYC reporters (default: `lcov`) |
| `teez_reporter` | teez coverage reporter id (default: `lcov`) |
| `output` | Optional teez coverage artifact path |
| `min_line_rate` | Minimum line coverage threshold |
| `include` / `exclude` | File globs forwarded to NYC |
| `extension` | File extensions forwarded to NYC |
| `temp_dir` | NYC temp directory |

With `teez run --with-coverage`, the plugin runs:

```bash
npx nyc --reporter=lcov <mocha|jest> ...
```

Configure NYC via `runners.p5js.coverage`.

## Test IDs

`teez list` prefers tool-native listing:

- **Jest**: `npx jest --listTests --json`
- **Mocha**: `npx mocha --dry-run`

When listing fails, the plugin falls back to discovered test file paths.

During runs, individual results use `file::test name` when a suite file is known; file-level `PASS` / `FAIL` lines use the file path as the id.

## Requirements

- `npx` on `PATH`
- Project dependencies installed (`npm install`) so Mocha/Jest/NYC resolve correctly
