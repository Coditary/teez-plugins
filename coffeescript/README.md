# teez CoffeeScript Runner

teez runner plugin for legacy CoffeeScript test suites using **Mocha** or **Jasmine**.

## Discovery

Matches Node projects that contain `package.json` and at least one `**/*.coffee` file.

| Manifest field | Value |
|----------------|-------|
| `requires` | `npx` |
| `anchors` | `package.json` |
| `glob_anchors` | `**/*.coffee` |
| `include` | `**/*_spec.coffee`, `**/spec/**` |
| `priority` | `115` |

## Framework selection

The plugin auto-detects the test runner from `package.json`:

1. Explicit `runners.coffeescript.framework = "mocha"` or `"jasmine"`
2. `jasmine` / `jasmine-node` dependency or script → Jasmine
3. `mocha` dependency or script → Mocha
4. Default: Mocha

CoffeeScript compilation is registered via `--require coffeescript/register` (or `coffee-script/register` when the older package is present).

## Usage

Point teez at your plugin directory:

```lua
-- teez.config.lua
return {
  plugins_dir = "/path/to/teez-plugins/coffeescript",
  plugins = { "coffeescript" },
  runners = {
    ["coffeescript"] = {
      framework = "mocha", -- optional
      args = { "--recursive" },
      reporter = "spec",
      timeout = 5000,
    },
  },
}
```

Or copy `teez-plugin-coffeescript.{json,lua}` into your project `plugins/` folder.

### Commands

```bash
teez discover .
teez list .
teez run . --simple
teez run . --with-coverage
```

## `teez list`

- **Mocha**: runs `npx mocha --reporter json --require <coffee-register> …` and returns `file::fullTitle` IDs (falls back to spec file paths when JSON collection fails).
- **Jasmine**: discovers spec files (`*_spec.coffee`, files under `spec/`) and lists them by relative path.

CLI filters (`-n`, `-t`, `-f`) are applied in `list` via teez's `filter.matches`.

## `teez run`

- **Mocha**: `npx mocha --reporter spec --require <coffee-register> [runner.args] [files]`
- **Jasmine**: `npx jasmine [runner.config] [files]` with `NODE_OPTIONS=--require <coffee-register>`

Filter patterns map to Mocha `--grep` / Jasmine `--filter`.

## Output parsing

`parse_line` understands common Mocha `--reporter spec` and Jasmine console output:

- pass: `✓` / `✔` lines (optional duration)
- fail: numbered `1) …` lines (Mocha) or `✗` lines (Jasmine)
- suite: indented suite titles → `start` events

## Coverage

Enable with `teez run . --with-coverage` and configure `runners.coffeescript.coverage`:

```lua
runners = {
  ["coffeescript"] = {
    coverage = {
      enabled = true,
      command = "nyc",           -- or "istanbul"
      reporter = "lcov",
      report_dir = "coverage",
      output = "coverage/lcov.info",
      extension = { ".coffee" },
      nyc_args = { "--all" },
      min_line_rate = 0.8,
    },
  },
}
```

Coverage runs through `npx nyc … mocha|jasmine` with the CoffeeScript register preloaded.

## Runner options

| Key | Description |
|-----|-------------|
| `framework` | `"mocha"` or `"jasmine"` |
| `coffee_require` | Override Node require hook (default: auto) |
| `args` | Extra CLI args passed to mocha/jasmine |
| `reporter` | Mocha reporter (default: `spec`) |
| `timeout` | Mocha timeout in ms |
| `config` | Jasmine `--config=` path |
| `jasmine_config` | Sets `JASMINE_CONFIG_PATH` |
| `files` | Explicit spec file list (relative or absolute) |
| `include` / `exclude` | Extra glob patterns merged with manifest defaults |
| `grep` | Explicit grep/filter pattern |
| `coverage` | nyc/istanbul settings (see above) |

## Example project layout

```
my-app/
├── package.json
├── lib/
│   └── widget.coffee
└── test/
    └── widget_spec.coffee
```

```json
{
  "devDependencies": {
    "coffeescript": "^2.7.0",
    "mocha": "^10.0.0"
  },
  "scripts": {
    "test": "mocha --require coffeescript/register 'test/**/*_spec.coffee'"
  }
}
```

## Requirements

- Node.js with `npx` on `PATH`
- Project dependencies: `mocha` or `jasmine`, plus `coffeescript` or `coffee-script`
- Spec files matching `**/*_spec.coffee` or `**/spec/**/*.coffee`
