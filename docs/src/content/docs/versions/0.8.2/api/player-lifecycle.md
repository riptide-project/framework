---
slug: versions/0.8.2/api/player-lifecycle
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

:::caution[Use the Riptide argument, not self fields]
Retroactive `OnPlayerAdded` calls execute **before** the `Init` phase. This means any fields you set on `self` inside `Init` (like `self.State = Riptide.State`) are **not yet available** when the retroactive hook fires.

**Always use the `Riptide` argument directly** inside lifecycle hooks:
```lua
-- ✅ Safe — uses the Riptide argument directly
function MyService:OnPlayerAdded(Riptide, player)
    Riptide.State:SetForPlayer(player, "coins", 100)
end

-- ❌ Unsafe — self.State may be nil if called before Init
function MyService:OnPlayerAdded(Riptide, player)
    self.State:SetForPlayer(player, "coins", 100)
end
```
:::

:::note
Retroactive calls ensure that if a player connects before the framework finishes initializing, they still receive their `OnPlayerAdded` hook. No players are missed.
:::

---

### `OnPlayerRemoving`

```lua
function MyService:OnPlayerRemoving(Riptide: Riptide, player: Player)
```

Called when a player is leaving the server (`Players.PlayerRemoving`). By this point, all modules have completed their `Init` and `Start` phases, so it is safe to read `self` fields here.

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
PlayerLifecycle:Start()                       ← retroactive OnPlayerAdded for existing players
    │
    ▼
Init Phase (synchronous)                      ← self.* fields are set here
    │
    ▼
Start Phase (task.spawn)                      ← game logic begins
    │
    ▼
Players.PlayerAdded → OnPlayerAdded(...)      ← new players (Init is done, self.* is safe)
    │
    ▼
Players.PlayerRemoving → OnPlayerRemoving(...)
    │
    ▼
StateReplication:_onPlayerRemoving(player)    ← automatic cleanup
```

:::important
For **retroactive** calls (players already connected at launch), hooks fire **before Init**. For players joining **after** launch, hooks fire **after** Init and Start. Always prefer the `Riptide` argument to be safe in both cases.
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
type Riptide = RiptidePkg.Riptide

local SessionService = {}

SessionService._sessions = {} :: { [number]: number }

function SessionService:Init(Riptide: Riptide)
    -- nothing to inject
end

function SessionService:OnPlayerAdded(Riptide: Riptide, player: Player)
    -- Use Riptide argument directly (safe for retroactive calls)
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
