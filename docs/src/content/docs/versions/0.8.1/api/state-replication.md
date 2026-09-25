---
slug: versions/0.8.1/api/state-replication
title: State Replication
description: Server-authoritative global and per-player state synchronization.
---


The `StateReplication` module provides minimal, server-authoritative state synchronization. The server owns all state; clients receive automatic snapshot sync on connect and delta updates in real-time.

Access via `Riptide.State`.

## Types

```lua
type Callback = (value: any) -> ()

type StateReplicationAPI = {
    Events: { Delta: string, Snapshot: string },

    -- Server-only
    Set: (self, key: string, value: any) -> (),
    SetForPlayer: (self, player: any, key: string, value: any) -> (),
    UpdateForPlayer: (self, player: any, key: string, updater: (oldValue: any) -> any) -> any,

    -- Shared
    Get: (self, key: string, player: any?) -> any,

    -- Client-only
    Subscribe: (self, key: string, callback: Callback) -> () -> (),
    RequestSync: (self) -> boolean,
}
```

## Scopes

State has two scopes:

| Scope        | Description                                            | Example     |
|-------------|--------------------------------------------------------|-------------|
| **Global**   | Shared across all players. Set with `Set()`.          | `"matchPhase"`, `"serverTime"` |
| **Player**   | Private to one player, overrides global. Set with `SetForPlayer()`. | `"coins"`, `"inventory"` |

On the client, `Get(key)` resolves **player-scoped** value first, falling back to **global** if no player override exists.

---

## Server-Only Methods

### `Set`

```lua
State:Set(key: string, value: any) -> ()
```

Sets a **global** state value and broadcasts a delta to all connected clients.

```lua
Riptide.State:Set("matchPhase", "Intermission")
Riptide.State:Set("serverTime", os.time())
```

---

### `SetForPlayer`

```lua
State:SetForPlayer(player: Player, key: string, value: any) -> ()
```

Sets a **player-scoped** state value. Only the target player receives the delta.

```lua
Riptide.State:SetForPlayer(player, "coins", 500)
```

:::note
Player state overrides global state for that player. If a global key `"coins"` is `0` but the player-scoped key is `500`, that player's client will see `500`.
:::

---

### `UpdateForPlayer`

```lua
State:UpdateForPlayer(player: Player, key: string, updater: (oldValue: any) -> any) -> any
```

Atomically updates a player-scoped value using a callback. Returns the new value.

```lua
local newCoins = Riptide.State:UpdateForPlayer(player, "coins", function(old)
    return (old or 0) + 50
end)
print("Player now has", newCoins, "coins")
```

---

## Shared Methods

### `Get`

```lua
State:Get(key: string, player: Player?) -> any
```

Reads a state value.

**Server** — returns the player-scoped value if `player` is given and a player override exists, otherwise returns the global value:

```lua
local globalPhase = Riptide.State:Get("matchPhase")
local playerCoins = Riptide.State:Get("coins", player)
```

**Client** — ignores the `player` parameter. Resolves player-scoped first, then falls back to global:

```lua
local coins = Riptide.State:Get("coins")
```

---

## Client-Only Methods

### `Subscribe`

```lua
State:Subscribe(key: string, callback: Callback) -> () -> ()
```

Subscribes to changes on a specific key. The callback is invoked:
1. **Immediately** with the current resolved value (synchronous).
2. On every subsequent change (via delta or snapshot sync).

Returns an **unsubscribe** function.

```lua
local unsubscribe = Riptide.State:Subscribe("coins", function(value)
    coinLabel.Text = "Coins: " .. tostring(value or 0)
end)

-- Later, when no longer needed:
unsubscribe()
```

:::tip
Always call the unsubscribe function when the UI element or controller is destroyed to prevent memory leaks.
:::

---

### `RequestSync`

```lua
State:RequestSync() -> boolean
```

Manually requests a full state snapshot from the server. This is called **automatically** during initialization, but you can call it manually to force a re-sync.

Returns `true` on success, `false` on failure (e.g., server unreachable or called on server).

```lua
local ok = Riptide.State:RequestSync()
if ok then
    print("State re-synced!")
end
```

---

## Sync Protocol

```
Client connects → InvokeServer("__riptide_state_snapshot")
Server responds with:
  {
    global = { ... },
    globalVersions = { ... },
    player = { ... },
    playerVersions = { ... },
  }

After initial sync, deltas arrive via:
  FireClient(player, "__riptide_state_delta", {
    scope = "global" | "player",
    key = "...",
    value = ...,
    version = number,
  })
```

- Each key has a monotonically increasing **version** per scope.
- The client discards deltas with a version ≤ the current known version (idempotent).
- On player leave, the server automatically cleans up all player-scoped state via `PlayerLifecycle`.
