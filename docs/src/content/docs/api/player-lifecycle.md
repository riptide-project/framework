---
title: Player Lifecycle
description: Server-side player lifecycle hooks for modules.
---


The `PlayerLifecycle` module provides centralized, server-side hooks that Riptide automatically calls on your modules when players join or leave.

:::important
Player Lifecycle is **server-only**. The hooks are only called on modules loaded on the server.
:::

## Hooks

Instead of manually connecting to `Players.PlayerAdded` and `Players.PlayerRemoving` inside every service, expose these methods on your module table and Riptide calls them for you.

### `OnPlayerAdded`

```lua
function MyService:OnPlayerAdded(Riptide: Riptide, player: Player)
```

Called when a player joins the server. Also called for all players already connected after the framework finishes module and plugin initialization.

```lua
function CoinsService:OnPlayerAdded(Riptide, player)
    Riptide.State:SetForPlayer(player, "coins", 100)
    print(player.Name .. " joined — gave 100 starting coins")
end
```

:::note[Injected server API]
`OnPlayerAdded` runs after module `Init`, so fields initialized in `Init` are available. The injected `Riptide` argument is already the server API, so autocomplete only exposes server-side methods.

```lua
-- ✅ Preferred
function MyService:OnPlayerAdded(Riptide, player)
    Riptide.State:SetForPlayer(player, "coins", 100)
end

-- Also valid if you assigned self.State in Init
function MyService:OnPlayerAdded(Riptide, player)
    self.State:SetForPlayer(player, "coins", 100)
end
```
:::

:::note
Existing-player replay ensures that if a player connects before the framework finishes initializing, they still receive their `OnPlayerAdded` hook. No players are missed.
:::

---

### `OnPlayerRemoving`

```lua
function MyService:OnPlayerRemoving(Riptide: Riptide, player: Player)
```

Called when a player is leaving the server (`Players.PlayerRemoving`). By this point, all modules have completed `Init` and the start phase has been dispatched, so it is safe to read fields prepared during `Init`.

```lua
function DataService:OnPlayerRemoving(Riptide, player)
    local coins = Riptide.State:Get("coins", player)
    self:SaveToDataStore(player.UserId, coins)
    print(player.Name .. " leaving — saved " .. coins .. " coins")
end
```

---

## Execution Order

```
Server starts
    │
    ▼
Init Phase (synchronous)                      ← self.* fields are set here
    │
    ▼
Plugin Start readiness barrier                ← framework extensions become ready before player replay
    │
    ▼
PlayerLifecycle:Start()                       ← existing players replayed after plugin readiness
    │
    ▼
Start Phase (task.spawn)                      ← game logic begins
    │
    ▼
Players.PlayerAdded → OnPlayerAdded(...)      ← new players
    │
    ▼
Players.PlayerRemoving → OnPlayerRemoving(...)
    │
    ▼
StateReplication:_onPlayerRemoving(player)    ← automatic cleanup
```

:::important
Existing-player replay happens after module initialization and plugin Start dispatch, so lifecycle hooks can use fields prepared during `Init` and plugins can observe existing players.
:::

---

## Automatic Cleanup

The `PlayerLifecycle` module automatically triggers `StateReplication:_onPlayerRemoving(player)` **after** your `OnPlayerRemoving` hooks run. This allows your modules to safely read player-scoped state during shutdown, and then clears it from the `StateReplication` registry, preventing stale data and memory leaks.

---

## Error Handling

If a hook throws an error, it is caught via `xpcall` and logged. **Other modules' hooks continue to execute** — one failing module does not block the rest.

```
[PlayerLifecycle] Error in OnPlayerAdded for CoinsService:
<stack trace>
```

---

## Full Example

```lua
--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RiptidePkg = require(ReplicatedStorage.Packages.Riptide)
type Riptide = RiptidePkg.RiptideServer

local SessionService = {}

SessionService._sessions = {} :: { [number]: number }

function SessionService:Init(Riptide: Riptide)
    -- nothing to inject
end

function SessionService:OnPlayerAdded(Riptide: Riptide, player: Player)
    -- Existing-player replay runs after Init.
    self._sessions[player.UserId] = os.time()
    Riptide.State:SetForPlayer(player, "sessionStart", os.time())
end

function SessionService:OnPlayerRemoving(Riptide: Riptide, player: Player)
    local startTime = self._sessions[player.UserId]
    if startTime then
        local duration = os.time() - startTime
        print(player.Name .. " played for " .. duration .. "s")
    end
    self._sessions[player.UserId] = nil
end

return SessionService
```
