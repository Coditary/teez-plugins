# teez Minitest runner

teez runner plugin for [Ruby Minitest](https://github.com/minitest/minitest) projects.

## Discovery

Matches Ruby projects that contain a `Gemfile` or `Rakefile` and have Minitest-style files under `test/`:

- `**/test/**/*_test.rb`
- `**/test/**/test_*.rb`

Requires `ruby` on `PATH`.

## Usage

Point teez at your project and pin the plugin if needed:

```lua
return {
  plugins_dir = "/path/to/teez-plugins/minitest",
  plugins = { "minitest" },
  runners = {
    minitest = {
      -- optional overrides
    },
  },
}
```

Or copy the manifest + Lua file into your project `plugins/` directory.

```bash
teez discover .
teez list .
teez run . --simple
teez run . --with-coverage
```

## Listing tests

`teez list` collects:

1. Test files discovered via the configured `include` / `exclude` globs
2. Rake tasks from `rake -T test` (or `bundle exec rake -T test` when a `Gemfile` is present)

Rake tasks are exposed as IDs like `rake:test` or `rake:test:models`.

## Running tests

Execution strategy:

| Condition | Command |
|-----------|---------|
| `Rakefile` defines a `test` task and no explicit files are selected | `rake test` or `bundle exec rake test` |
| Filter selects a `rake:...` ID | `rake <task>` or `bundle exec rake <task>` |
| Otherwise | `ruby -Itest -v test/...` or `bundle exec ruby -Itest -v test/...` |

By default the plugin enables verbose Minitest output (`-v` / `TESTOPTS=-v`) so stdout includes one line per test method.

CLI filters:

- File/name filters from teez are applied when listing
- Name patterns are forwarded to Minitest as `-n <pattern>`

## Configuration

All options live under `runners.minitest` in `teez.config.lua`:

| Key | Default | Description |
|-----|---------|-------------|
| `test_dir` | `"test"` | Load path / directory passed to `ruby -I` |
| `include` | manifest defaults | Glob patterns for test files |
| `exclude` | `["**/*.teez.lua"]` | Glob patterns to skip |
| `use_rake` | auto | Prefer `rake test` when a matching task exists |
| `bundle` | auto | Use `bundle exec` when `Gemfile` exists |
| `verbose` | `true` | Pass `-v` / `TESTOPTS=-v` for parseable output |
| `args` | none | Extra CLI args appended to the run command |
| `env` | none | Extra environment variables for the child process |

### Coverage (SimpleCov)

Enable project-side SimpleCov when `ENV["COVERAGE"]` is set, then configure the reporter output:

```lua
runners = {
  minitest = {
    coverage = {
      report = "coverage/lcov.info",
      reporter = "lcov",
      output = "coverage/teez.msgpack",
      min_line_rate = 0.8,
      env = {
        COVERAGE = "true",
      },
    },
  },
},
```

Example `test/test_helper.rb` hook:

```ruby
if ENV["COVERAGE"]
  require "simplecov"
  require "simplecov-lcov"
  SimpleCov::Formatter::LcovFormatter.config.report_with_single_file = true
  SimpleCov.formatter = SimpleCov::Formatter::MultiFormatter.new([
    SimpleCov::Formatter::LcovFormatter,
    SimpleCov::Formatter::HTMLFormatter,
  ])
  SimpleCov.start
end
```

Run with:

```bash
teez run . --with-coverage
```

## Output parsing

`parse_line` understands:

- Verbose result lines: `UserTest#test_valid = 0.01 s = .`
- Progress characters: `.` pass, `F`/`E` fail, `S` skip
- Minitest failure/error blocks (`1) Failure:` …)
- Summary lines (`N runs, …`)

Failure messages use the `msg` field per the teez event contract.
