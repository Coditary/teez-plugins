# teez plugins

Optional runner plugins distributed separately from teez-core built-ins (pytest, ctest, worker).

| Plugin | Path | Description |
|--------|------|-------------|
| vitest | [vitest/](vitest/) | Node/Vitest test runner adapter |

Install the **teez CLI** with ReqPack from [teez-cli releases](https://github.com/Coditary/teez-cli/releases).
Install **optional plugins** via `rqp-plugin-teez`:

```bash
rqp install ./packaging/rqp-plugin-teez
rqp install teez vitest
```

Plugins are installed to `~/.local/share/teez/plugins/` and discovered by teez after project plugins.
