---
slug: versions/0.3.0/guides/module-lifecycle
title: Module lifecycle
description: Load, initialize, and look up modules in Riptide 0.3.0.
---

A `ModuleScript` inside a configured `ModulesFolder` returns a table. Riptide registers it and runs its optional lifecycle methods.

```lua
-- ServerModules/CounterService.lua
local CounterService = {}

function CounterService:Init(riptide)
    self.count = 0
end

function CounterService:Start(riptide)
    print("CounterService is ready")
end

function CounterService:Add(amount)
    self.count += amount
    return self.count
end

return CounterService
```

The server entry point passes `ServerModules` to `Riptide.Server.Launch({ ModulesFolder = ... })`. For client controllers, put a similar module in the client folder and call `Riptide.Client.Launch` from a client script.

## Lifecycle order

1. Riptide loads and registers configured modules.
2. It calls each module's `Init(riptide)` synchronously. Use this phase to obtain dependencies and set up listeners.
3. It schedules `Start(riptide)` after initialization. Use this phase to begin gameplay logic that depends on other initialized modules.

## Finding another module

On the server, call `riptide.GetService("CounterService")`. On the client, call `riptide.GetController("CounterController")`. The methods are side-specific; do not use a client lookup on the server.

The registry uses the module's `ModuleScript.Name` as its lookup name. Give modules distinct names so `GetService("CounterService")` and `GetController("CounterController")` point to the intended module.

This release configures one `ModulesFolder` per side. Shared and multiple folder configuration arrived in 0.5.0.

**Next:** [Use named networking](../../api/network/) or [attach a tagged component](../../api/component-service/).

---

This page describes **Riptide 0.3.0**. Check the [original release guide](../../readme/) and [tagged source](https://github.com/riptide-project/framework/tree/v0.3.0) for release-specific details.
