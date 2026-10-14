# teez Perl runner (`perl`)

teez runner plugin for [Perl](https://www.perl.org/) projects using [Test::More](https://metacpan.org/pod/Test::More) via [`prove`](https://metacpan.org/pod/App::Prove).

## Discovery

Matches projects containing any of:

- `Makefile.PL`
- `cpanfile`
- `META.json`

Requires `prove` on `PATH`.

## Test files

- `**/t/*.t`
- `**/*_test.pl`

## Usage

Point teez at your plugin directory:

```lua
return {
  plugins_dir = "/path/to/teez-plugins/perl",
  plugins = { "perl" },
}
```

Or copy `teez-plugin-perl.json` and `teez-plugin-perl.lua` into your project's `plugins/` directory.

```bash
teez discover .
teez list .
teez run . --simple
```

## Commands

| teez action | prove invocation |
|-------------|------------------|
| `list` | `prove --collect -r t/` |
| `run` | `prove -lv t/` (default) or `prove -lr t/` |

## Configuration

Configure via `runners.perl` in `teez.config.lua`:

```lua
return {
  runners = {
    perl = {
      test_dir = "t",       -- test directory (default: "t")
      lib = true,             -- pass -l (default: true)
      recursive = false,      -- pass -r on run (default: false; list always uses -r)
      verbose = true,         -- pass -v on run (default: true)
      args = {},              -- extra prove arguments
      coverage = false,       -- enable Devel::Cover via HARNESS_PERL_SWITCHES
      coverage_opts = nil,    -- optional Devel::Cover module options
    },
  },
}
```

Set `verbose = false` and `recursive = true` to run with `prove -lr t/`.

### Coverage

Enable [Devel::Cover](https://metacpan.org/pod/Devel::Cover) in project config:

```lua
runners = {
  perl = {
    coverage = true,
  },
},
```

For `teez run --with-coverage`, the plugin runs tests with `HARNESS_PERL_SWITCHES=-MDevel::Cover` and collects an LCOV report via `cover -report lcov`.

Install coverage tools in your Perl environment:

```bash
cpanm Devel::Cover
```

## TAP parsing

`parse_line` maps prove stdout to teez events:

| TAP line | Event |
|----------|-------|
| `ok N - description` | `pass` |
| `ok N # skip reason` | `skip` |
| `not ok N - description` | `fail` |
| other lines | `output` |
