# teez ServiceNow ATF Runner

teez runner plugin for [ServiceNow Automated Test Framework (ATF)](https://www.servicenow.com/docs/bundle/zurich-application-development/page/build/system-update-api/concept/atf-overview.html).

## Discovery

Matches projects with:

- `snow.properties` (instance credentials / scope)
- `src/**` tree (scoped application source)
- ATF artifacts under `**/atf/**` or `**/*_test.xml`

Requires the ServiceNow CLI (`snc`) on `PATH`. If your enterprise uses REST-only execution, set `runners.servicenow.command` to `curl` (or another HTTP client) and provide `run_command` / `list_command`.

## Quick start

```lua
-- teez.config.lua
return {
  plugins_dir = "/path/to/teez-plugins/servicenow",
  plugins = { "servicenow" },
  runners = {
    servicenow = {
      instance = "dev12345",
      -- Optional enterprise overrides:
      -- command = "curl",
      -- run_command = "curl -sS -X POST https://dev12345.service-now.com/api/now/atf/runner/run",
      -- list_command = "curl -sS https://dev12345.service-now.com/api/now/table/sys_atf_test?sysparm_fields=sys_id,name",
    },
  },
}
```

```bash
teez discover .
teez list .
teez run . --simple
```

## Runner options

| Key | Description |
|-----|-------------|
| `command` | Executable for run/list when not using full `run_command` / `list_command` (default: `snc`) |
| `run_command` | Full run invocation string; appended with `args`, `instance`, `suite`, `test`, `browser`, and target path |
| `list_command` | Full list invocation string; same suffix rules as `run_command` |
| `args` | Extra CLI arguments appended to every invocation |
| `instance` | ServiceNow instance name (`--instance`) |
| `suite` | ATF suite sys_id (`--suite`) |
| `test` | Single ATF test sys_id (`--test`) |
| `browser` | Browser profile for UI tests (`--browser`) |
| `include` / `exclude` | Glob patterns for metadata discovery (default: manifest `include`) |
| `env` | Extra environment variables for child process |
| `cwd` | Working directory for child process |

## List behavior

1. `list_command` when set (parsed as whitespace-separated command + args)
2. `snc atf list --format json` (plus runner options)
3. Fallback: scan `include` globs for ATF XML metadata (`sys_id`, `<name>`)

CLI filters (`-n`, `-t`, `-f`) are applied after collection.

## Run behavior

1. `run_command` when set
2. `command` + runner options + target path (REST/curl mode)
3. Default: `snc atf run --format json` + runner options + target path

## Output parsing

`parse_line` accepts:

- JSON lines (`status` / `result` / `event` fields)
- Text prefixes: `PASS:`, `FAIL:`, `SKIP:`, `START:`, `[PASS]`, `[FAIL]`
- Common ATF log lines (`Test <name> passed/failed`)

Unrecognized lines are emitted as `output` events.

## Coverage

Not supported by this plugin. ATF and instance governance enforce platform coverage separately.

## REST / curl example

```lua
runners = {
  servicenow = {
    command = "curl",
    list_command = "curl -sS -u ${SN_USER}:${SN_PASS} https://instance.service-now.com/api/now/table/sys_atf_test?sysparm_fields=sys_id,name",
    run_command = "curl -sS -u ${SN_USER}:${SN_PASS} -H Content-Type:application/json -d @payload.json https://instance.service-now.com/api/now/atf/runner/run",
    env = {
      SN_USER = os.getenv("SN_USER"),
      SN_PASS = os.getenv("SN_PASS"),
    },
  },
}
```

Use your organization's approved ATF REST endpoint and authentication model.
