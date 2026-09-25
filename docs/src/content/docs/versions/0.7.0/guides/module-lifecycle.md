---
slug: versions/0.7.0/guides/module-lifecycle
title: Module lifecycle
description: Load, initialize, and look up modules in Riptide 0.7.0.
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

The registry uses a **canonical ID** based on the path below `ModulesFolder`. For example, `Economy/PlayerData` is a reliable lookup key. A short name such as `PlayerData` works only when it is unique. If two folders contain `Data`, use the full path; the ambiguous `Data` alias resolves to `nil`.

You can pass multiple folders and an optional `SharedModulesFolder` to `Launch`. Shared folders are processed before the side-specific folders. A module found in more than one configured folder is loaded once.

**Next:** [Use named networking](../../api/network/) or [attach a tagged component](../../api/component-service/).

---

This page describes **Riptide 0.7.0**. Check the [original release guide](../../readme/) and [tagged source](https://github.com/riptide-project/framework/tree/v0.7.0) for release-specific details.
