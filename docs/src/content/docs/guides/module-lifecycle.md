---
title: Module Lifecycle
description: How Riptide loads, initialises, and starts every module — and what you can safely do in each phase.
---


Riptide uses a **three-phase lifecycle** that gives every module a well-defined slot for initialization. Understanding these phases is the key to writing bug-free, race-condition-free code.

---

## The Three Phases

```
╔═══════════╗      ╔════════════╗      ╔═══════════╗
║   LOAD    ║ ───▶ ║    INIT    ║ ───▶ ║   START   ║
╚═══════════╝      ╚════════════╝      ╚═══════════╝

All modules       All :Init()s       All :Start()s
are require()d    run in sequence,   run in parallel
first.            synchronously.     (task.spawn).
```

### Framework Extension Phase — Plugins

Before game modules load, Riptide loads and initializes configured plugins. Plugins are treated as framework extensions: they can expose `PublicAPI`, register sandbox-owned resources, and prepare infrastructure that services/controllers consume later.

Plugin `Start` runs as a bounded readiness barrier after game module `Init`, but before server player lifecycle replay and game module `Start`. A plugin can yield in `Start`, but it should only do bounded setup there; long-running loops should be spawned inside `Start`.

### Phase 1 — Load

Riptide `require()`s every Lua module it finds in the folders you passed to `Launch`. No lifecycle methods are called yet — this is pure module loading. Every return value is stored internally by its module name.

### Phase 2 — Init

Riptide calls `:Init(Riptide)` on every module that defines it, **one at a time**, in load order. The injected `Riptide` argument is already side-specific: server services receive `Riptide.Server`, and client controllers receive `Riptide.Client`. Because `Init` runs in sequence, you can safely call `Riptide.GetService()` or `Riptide.GetController()` to access other modules — they are already loaded, even if their own `Init` hasn't run yet.

:::caution[Do not yield in Init]
`Init` runs synchronously. **Never** call `task.wait`, `Instance:WaitForChild`, `RemoteEvent.OnServerEvent:Wait()`, or any other yielding call inside `Init`. Yielding here blocks all other modules from initializing and will likely deadlock your game.
:::

### Phase 3 — Start

Once **every** module has finished `Init`, Riptide calls `:Start(Riptide)` on each module — wrapped in `task.spawn`, so they all run **concurrently**. You can yield freely here: start loops, wait for events, kick off async work, etc.

---

## Rule of Thumb

| Task | Phase |
|---|---|
| Store a reference to another Service/Controller | `Init` |
| Register a `Network` event handler | `Init` |
| Set initial `State` values | `Init` |
| Set up `ComponentService` | `Init` |
| Start a while-true game loop | `Start` |
| `task.wait` or `WaitForChild` | `Start` |
| Connect to `Players.PlayerAdded` signals | `Start` _(or use `OnPlayerAdded`)_ |
| Connect a UI event (GuiButton.Activated) | `Start` |

---

## Player Hooks

Two additional lifecycle methods are automatically called for you:

| Method | When |
|---|---|
| `:OnPlayerAdded(Riptide, player)` | A player joins. Also replays for existing players after plugin readiness and module initialization. |
| `:OnPlayerRemoving(Riptide, player)` | A player leaves. |

---

## Annotated Full Example

```lua
-- ServerScriptService/Services/DataService.lua
--!strict

local DataService = {}

-- Called once, in sequence, before Start.
function DataService:Init(Riptide)
    -- ✅ Safe: grab a reference to another service.
    -- Even if EconomyService's Init hasn't run yet, it IS loaded.
    self.Economy = Riptide.GetService("EconomyService")

    -- ✅ Safe: register network handlers.
    Riptide.Network.Register("GetCoins", function(player)
        return Riptide.State:Get("coins", player)
    end)

    -- ❌ WRONG: never yield in Init.
    -- task.wait(1)  ← this would block all other modules!
end

-- Called once everything has Init'd. Runs in its own task.spawn.
function DataService:Start(Riptide)
    -- ✅ Safe to yield in Start.
    while true do
        task.wait(30)
        self:_autosaveAll()
    end
end

-- Fires for players already online AND new joiners.
function DataService:OnPlayerAdded(Riptide, player)
    -- ✅ Safe to yield (runs in task.spawn).
    local data = self:_loadFromDataStore(player)
    Riptide.State:SetForPlayer(player, "coins", data.coins)
    Riptide.State:SetForPlayer(player, "level", data.level)
end

function DataService:OnPlayerRemoving(Riptide, player)
    self:_saveToDataStore(player)
end

-- Private helpers (prefixed with _ by convention)
function DataService:_loadFromDataStore(player)
    -- task.wait() is fine here — called from Start/OnPlayerAdded
    task.wait(0.1)  -- simulated async load
    return { coins = 0, level = 1 }
end

function DataService:_saveToDataStore(player)
    print("Saving data for", player.Name)
end

function DataService:_autosaveAll()
    print("Autosaving all player data...")
end

return DataService
```

---

## Accessing Other Modules

```lua
function MyService:Init(Riptide)
    -- Server: get a Service by name
    local Economy = Riptide.GetService("EconomyService")

    -- Client: get a Controller by name
    local UI = Riptide.GetController("UIController")

    -- Shared modules (loaded by SharedModulesFolder) are
    -- accessed via require() directly, like normal Lua modules.
    local Config = require(ReplicatedStorage.SharedModules.Config)
end
```

:::note[Dot not colon]
`GetService` and `GetController` are plain functions — call them with **dot syntax**, not colon syntax. Using colon syntax passes `Riptide` as the name argument, which will return `nil`.
:::

---

## Next Steps

- **[Network](../../api/network/)** — register and fire remote events.
- **[State Replication](../../api/state-replication/)** — sync data from server to clients.
- **[Utilities](../../api/utilities/)** — `Trove`, `EventBus`, `Guard`, `Async`.
