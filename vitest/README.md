# teez vitest runner plugin

Vitest adapter for teez. Discovers projects with `vitest.config.*` or `vite.config.*` and runs tests via `npx vitest`.

## Install via ReqPack

```bash
rqp install teez vitest
```

Installs manifest + Lua into `~/.local/share/teez/plugins/`.

## Project override

```lua
return {
    runners = {
        vitest = {
            pattern = "unit",
            args = { "--pool=threads" },
        },
    },
}
```
