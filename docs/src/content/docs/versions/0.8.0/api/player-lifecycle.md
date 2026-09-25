---
slug: versions/0.8.0/api/player-lifecycle
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

Called when a player joins the server. Also called **retroactively** for all players already connected at the time the module is loaded.

```lua
function CoinsService:OnPlayerAdded(Riptide, player)
    Riptide.State:SetForPlayer(player, "coins", 100)
    print(player.Name .. " joined — gave 100 starting coins")
end
```

:::note
Retroactive calls ensure that if a player connects before the framework finishes initializing, they still receive their `OnPlayerAdded` hook. No players are missed.
:::

---

### `OnPlayerRemoving`

```lua
function MyService:OnPlayerRemoving(Riptide: Riptide, player: Player)
```

Called when a player is leaving the server (`Players.PlayerRemoving`).

```lua
function DataService:OnPlayerRemoving(Riptide, player)
    local coins = Riptide.State:Get("coins", player)
    self:SaveToDataStore(player.UserId, coins)
    print(player.Name .. " leaving — saved " .. coins .. " coins")
end
```

---

## Automatic Cleanup

The `PlayerLifecycle` module automatically triggers `StateReplication:_onPlayerRemoving(player)` **before** your `OnPlayerRemoving` hooks run. This clears all player-scoped state from the `StateReplication` registry, preventing stale data and memory leaks.

```
Player leaves
    │
    ▼
StateReplication:_onPlayerRemoving(player)   ← automatic cleanup
    │
    ▼
Module:OnPlayerRemoving(Riptide, player)     ← your hook
```

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
type Riptide = RiptidePkg.Riptide

local SessionService = {}

SessionService._sessions = {} :: { [number]: number }

function SessionService:Init(Riptide: Riptide)
    -- nothing to inject
end

function SessionService:OnPlayerAdded(Riptide: Riptide, player: Player)
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
