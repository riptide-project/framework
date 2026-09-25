---
slug: versions/0.8.0/guides/module-lifecycle
title: Module Lifecycle
description: How Riptide loads, initializes, and starts your modules.
---


Riptide uses a deterministic **3-phase lifecycle** to orchestrate your game modules. This eliminates circular-require issues and guarantees all dependencies are available before game logic runs.

## The Three Phases

### 1. Load Phase

Every `ModuleScript` descendant inside your configured `ModulesFolder` (and `SharedModulesFolder`) is `require()`'d. The returned table is registered in the internal module registry under a **canonical ID**.

```
SharedModulesFolder loaded first → ModulesFolder loaded second
```

:::note
Shared modules are loaded **before** side-specific modules, so server services and client controllers can depend on shared utilities.
:::

### 2. Init Phase (synchronous)

After all modules are loaded, Riptide calls `Init` on every module **synchronously** and in order:

```lua
function MyService:Init(Riptide: Riptide)
    -- Safe to call GetService / GetController here
    self.DataService = Riptide.GetService("DataService")

    -- Safe to register network handlers
    Riptide.Network.Register("FetchCoins", function(player)
        return self:GetCoins(player)
    end)
end
```

Since Init is synchronous, all modules have been loaded (but not yet started) when your Init runs. This is the correct place for dependency injection.

### 3. Start Phase (asynchronous)

After **all** Init calls complete, Riptide calls `Start` on every module via `task.spawn`:

```lua
function MyService:Start(Riptide: Riptide)
    -- All modules are fully initialized — safe to interact
    while true do
        self:TickGameLoop()
        task.wait(1)
    end
end
```

Since each `Start` runs in its own coroutine, one module yielding does not block others.

---

## Canonical Module IDs

Every module is registered with a **canonical ID** based on its relative path from the modules folder:

```
ModulesFolder/
├── Economy/
│   └── PlayerData.lua    → "Economy/PlayerData"
├── Combat/
│   └── DamageService.lua → "Combat/DamageService"
└── MatchService.lua      → "MatchService"
```

### Lookup Rules

```lua
-- Canonical ID — always works
Riptide.GetService("Economy/PlayerData")

-- Short alias — works only when the name is unique
Riptide.GetService("PlayerData")

-- Ambiguous alias — returns nil + warning
-- (e.g. two modules named "Utils" in different folders)
Riptide.GetService("Utils")  -- ⚠️ nil
```

---

## Module Getters

| Method                | Context     | Description                                    |
|-----------------------|-------------|------------------------------------------------|
| `Riptide.GetModule(name)` | Shared  | Universal module lookup by canonical ID or alias. |
| `Riptide.GetService(name)` | Server | Alias for `GetModule`. **Errors** if called on client. |
| `Riptide.GetController(name)` | Client | Alias for `GetModule`. **Errors** if called on server. |

:::caution
Calling `GetService` on the client or `GetController` on the server will throw a runtime error. Use the context-appropriate getter for type safety and clear intent.
:::

---

## Example Module

```lua
--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RiptidePkg = require(ReplicatedStorage.Packages.Riptide)
type Riptide = RiptidePkg.Riptide

local CoinsService = {}

function CoinsService:Init(Riptide: Riptide)
    self.State = Riptide.State

    Riptide.Network.Register("GetCoins", function(player)
        return self.State:Get("coins", player)
    end)
end

function CoinsService:Start(Riptide: Riptide)
    print("CoinsService is running!")
end

function CoinsService:OnPlayerAdded(Riptide: Riptide, player: Player)
    self.State:SetForPlayer(player, "coins", 100)
end

return CoinsService
```

---

## Lifecycle Summary

```
require() all ModuleScripts    ← Load Phase
            │
            ▼
Init(Riptide) — synchronous    ← Init Phase (inject deps)
            │
            ▼
Start(Riptide) — task.spawn    ← Start Phase (run logic)
```
