# teez runner plugins

Optional runner plugins for [teez](https://github.com/Coditary/teez-cli). Each subdirectory contains a JSON manifest, Lua adapter, and `README.md`.

This tree lives under `teez-plugins/` in the **teez** plugins workspace. Point `plugins_dir` at this directory (or the repo root with `plugins_dir = "teez-plugins"`).

## JavaScript / TypeScript

| Plugin | Framework | Path |
|--------|-----------|------|
| ava | AVA | [teez-plugins/ava/](ava/) |
| bun | Bun test | [teez-plugins/bun/](bun/) |
| cypress | Cypress | [teez-plugins/cypress/](cypress/) |
| deno | Deno test | [teez-plugins/deno/](deno/) |
| jest | Jest | [teez-plugins/jest/](jest/) |
| mocha | Mocha | [teez-plugins/mocha/](mocha/) |
| node-test | Node.js `node:test` | [teez-plugins/node-test/](node-test/) |
| playwright | Playwright | [teez-plugins/playwright/](playwright/) |
| vitest | Vitest | [teez-plugins/vitest/](vitest/) |
| webdriverio | WebdriverIO | [teez-plugins/webdriverio/](webdriverio/) |

## Other languages

| Plugin | Framework | Path |
|--------|-----------|------|
| go | `go test` | [teez-plugins/go/](go/) |
| rust | `cargo test` | [teez-plugins/rust/](rust/) |
| elixir | ExUnit / `mix test` | [teez-plugins/elixir/](elixir/) |
| erlang | EUnit / Common Test (`rebar3`) | [teez-plugins/erlang/](erlang/) |
| clojure | `clojure.test` / Kaocha | [teez-plugins/clojure/](clojure/) |
| r | testthat | [teez-plugins/r/](r/) |
| julia | Julia `Test` / `Pkg.test()` | [teez-plugins/julia/](julia/) |
| dart | `dart test` | [teez-plugins/dart/](dart/) |
| nim | Nim `unittest` / `nimble test` | [teez-plugins/nim/](nim/) |
| ocaml | Alcotest / `dune test` | [teez-plugins/ocaml/](ocaml/) |
| haskell | Tasty (`cabal` / `stack`) | [teez-plugins/haskell/](haskell/) |
| swift | XCTest / `swift test` | [teez-plugins/swift/](swift/) |
| minitest | Ruby Minitest | [teez-plugins/minitest/](minitest/) |
| junit | Java JUnit (Maven / Gradle) | [teez-plugins/junit/](junit/) |
| dotnet | .NET `dotnet test` | [teez-plugins/dotnet/](dotnet/) |
| kotlin | Kotlin / Gradle (`kotlin.test`) | [teez-plugins/kotlin/](kotlin/) |
| phpunit | PHPUnit | [teez-plugins/phpunit/](phpunit/) |
| scalatest | ScalaTest / sbt | [teez-plugins/scalatest/](scalatest/) |
| perl | Perl `prove` / Test::More | [teez-plugins/perl/](perl/) |
| pfunit | Fortran PFUnit / CTest | [teez-plugins/pfunit/](pfunit/) |

## More languages & specialized runtimes

| Plugin | Framework | Path |
|--------|-----------|------|
| zig | Zig `std.testing` | [teez-plugins/zig/](zig/) |
| crystal | Crystal Spec | [teez-plugins/crystal/](crystal/) |
| ada | Ada AUnit (`gprbuild` / `alr`) | [teez-plugins/ada/](ada/) |
| dlang | D `unittest` / `dub test` | [teez-plugins/dlang/](dlang/) |
| vlang | V `v test` | [teez-plugins/vlang/](vlang/) |
| pascal | FPCUnit / DUnitX | [teez-plugins/pascal/](pascal/) |
| racket | Racket `rackunit` | [teez-plugins/racket/](racket/) |
| lisp | Common Lisp FiveAM / ASDF | [teez-plugins/lisp/](lisp/) |
| prolog | SWI-Prolog PlUnit | [teez-plugins/prolog/](prolog/) |
| matlab | MATLAB Unit Testing | [teez-plugins/matlab/](matlab/) |
| bats | Bash Bats | [teez-plugins/bats/](bats/) |
| busted | Lua Busted | [teez-plugins/busted/](busted/) |
| forge | Foundry / Solidity | [teez-plugins/forge/](forge/) |
| gut | Godot GUT (GDScript) | [teez-plugins/gut/](gut/) |
| pester | PowerShell Pester | [teez-plugins/pester/](pester/) |
| flexunit | ActionScript FlexUnit | [teez-plugins/flexunit/](flexunit/) |
| abap | ABAP Unit (abapGit / abaplint) | [teez-plugins/abap/](abap/) |
| apex | Salesforce Apex (`sf`) | [teez-plugins/apex/](apex/) |
| vba | VBA / Rubberduck | [teez-plugins/vba/](vba/) |
| sasunit | SAS sasunit | [teez-plugins/sasunit/](sasunit/) |

## Specialized & legacy environments

| Plugin | Framework | Path |
|--------|-----------|------|
| spock | Groovy Spock (Gradle) | [teez-plugins/spock/](spock/) |
| grails | Grails + Spock | [teez-plugins/grails/](grails/) |
| scheme | Scheme SRFI-64 | [teez-plugins/scheme/](scheme/) |
| smalltalk | Smalltalk SUnit | [teez-plugins/smalltalk/](smalltalk/) |
| processing | Processing / ProcessingUnit | [teez-plugins/processing/](processing/) |
| autohotkey | AutoHotkey AUnit | [teez-plugins/autohotkey/](autohotkey/) |
| godot4 | Godot 4 built-in tests | [teez-plugins/godot4/](godot4/) |
| coffeescript | CoffeeScript (Mocha/Jasmine) | [teez-plugins/coffeescript/](coffeescript/) |
| wolfram | Wolfram Language UnitTesting | [teez-plugins/wolfram/](wolfram/) |
| stan | Stan / CmdStan | [teez-plugins/stan/](stan/) |
| fruit | Fortran FRUIT | [teez-plugins/fruit/](fruit/) |
| pawn | Pawn PawnUnit | [teez-plugins/pawn/](pawn/) |
| p5js | p5.js / Processing.js | [teez-plugins/p5js/](p5js/) |
| qtest | Qt QTest | [teez-plugins/qtest/](qtest/) |
| gdl | GDL / IDL | [teez-plugins/gdl/](gdl/) |
| tcl | Tcl TclTest | [teez-plugins/tcl/](tcl/) |
| servicenow | ServiceNow ATF | [teez-plugins/servicenow/](servicenow/) |
| labview | LabVIEW VI Tester | [teez-plugins/labview/](labview/) |
| openscad | OpenSCAD / BOSL2 | [teez-plugins/openscad/](openscad/) |
| rexx | Regina REXX | [teez-plugins/rexx/](rexx/) |

> **Note:** For Godot projects, `godot4` (priority 116) wins over `gut` (115) unless pinned in config.

## Usage

```lua
-- teez.config.lua (repo root)
return {
    plugins_dir = "teez-plugins",
    plugins = { "go", "rust" },  -- optional: pin runners
    runners = {
        go = { pattern = "TestFoo" },
        rust = { coverage_tool = "llvm-cov" },
    },
}
```

```bash
teez discover .
teez list .
teez run . --simple
teez run . --with-coverage   # when plugin supports build_coverage_run
```
