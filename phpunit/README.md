# teez PHPUnit Runner

teez runner plugin for [PHPUnit](https://phpunit.de/) projects.

## Discovery

Matches projects that contain any of:

- `phpunit.xml`
- `phpunit.xml.dist`
- `composer.json`

Requires `php` on `PATH`. Priority `115`.

## Installation

Copy this directory into your teez plugins folder, or point `plugins_dir` at it:

```lua
return {
  plugins_dir = "/path/to/teez-plugins/phpunit",
  plugins = { "phpunit" },
}
```

For a monorepo-style layout, place the plugin files in a shared plugins directory and reference the manifest name `phpunit`.

## Usage

```bash
teez discover .
teez list .
teez run . --simple
teez run . --with-coverage
```

## How it works

| Command | Behavior |
|---------|----------|
| `list` | Runs `php vendor/bin/phpunit --list-tests` when `vendor/bin/phpunit` exists; otherwise discovers `*Test.php` files via include globs |
| `run` | Runs `php vendor/bin/phpunit` (or `phpunit` on `PATH` as fallback) with `--colors=never --verbose --debug` |
| `parse_line` | Maps PHPUnit verbose/debug output and failure summaries to teez events (`pass`, `fail`, `skip`, `start`, `output`) |
| coverage | Adds `--coverage-clover` (default report: `coverage/clover.xml`) |

## Configuration

```lua
return {
  plugins_dir = "plugins",
  plugins = { "phpunit" },
  runners = {
    phpunit = {
      args = { "--stop-on-failure" },
      pattern = "UserTest",
      filter = "testCreate",
      include = { "**/tests/**", "**/*Test.php" },
      exclude = { "**/vendor/**" },
      coverage_output = "build/coverage/clover.xml",
    },
  },
}
```

| Key | Description |
|-----|-------------|
| `args` | Extra PHPUnit CLI arguments |
| `pattern` / `filter` | Passed as `--filter` (PHPUnit regex) |
| `include` / `exclude` | Glob patterns for file discovery fallback |
| `coverage_output` | Clover XML path for `--with-coverage` |

CLI filters (`-n`, `-f`, etc.) are forwarded where possible:

- name/pattern filters → `--filter`
- multiple explicit names → repeated `--filter` args on run
- post-filtering in `list` via teez `filter.matches`

## Test IDs

When using `--list-tests`, IDs look like:

```
Tests\Unit\ExampleTest::test_example
```

File discovery fallback uses paths such as `tests/Unit/ExampleTest.php`.

## Requirements

- PHP on `PATH`
- PHPUnit installed (typically `composer require --dev phpunit/phpunit`)
- For coverage: a code coverage driver (PCOV or Xdebug)
