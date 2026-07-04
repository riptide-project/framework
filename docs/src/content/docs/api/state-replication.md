---
title: State Replication
description: Server-authoritative global and per-player state synchronization.
---


The `StateReplication` module provides minimal, server-authoritative state synchronization. The server owns all state; clients receive automatic snapshot sync on connect and delta updates in real-time.

Prefer side-specific access through `Riptide.Server.State` or `Riptide.Client.State`. The root `Riptide.State` alias remains available for compatibility and dynamic shared code.

## Types

```lua
type Callback = (value: any) -> ()

type StateReplicationBaseAPI = {
    Events: { Delta: string, Snapshot: string },
    Get: (self, key: string, player: Player?) -> any,
}

type StateReplicationServerAPI = StateReplicationBaseAPI & {
    Set: (self, key: string, value: any) -> (),
    SetForPlayer: (self, player: Player, key: string, value: any) -> (),
    UpdateForPlayer: (self, player: Player, key: string, updater: (oldValue: any) -> any) -> any,
    TypedServer: <T>() -> T,
}

type StateReplicationClientAPI = StateReplicationBaseAPI & {
    Subscribe: (self, key: string, callback: Callback) -> () -> (),
    RequestSync: (self) -> boolean,
    TypedClient: <T>() -> T,
}
```

## Typed State Proxies

Maelstrom-2 adds typed key proxies for state schemas. Dynamic string methods remain available, but typed proxies give autocomplete for state keys and typed values.

### Client Schema

```lua
type ClientState = {
    coins: StateReplication.ClientKey<number>,
    matchPhase: StateReplication.ClientKey<"Intermission" | "Running">,
}

local State = Riptide.Client.State.TypedClient<ClientState>()

local coins = State.coins:Get()

local unsubscribe = State.matchPhase:Subscribe(function(phase)
    if phase == "Running" then
        showRoundUi()
    end
end)
```

### Server Schema

```lua
type ServerState = {
    coins: StateReplication.ServerKey<number>,
    matchPhase: StateReplication.ServerKey<"Intermission" | "Running">,
}

local State = Riptide.Server.State.TypedServer<ServerState>()

State.matchPhase:Set("Intermission")
State.coins:SetForPlayer(player, 100)

local newCoins = State.coins:UpdateForPlayer(player, function(old)
    return (old or 0) + 25
end)
```

:::note
Typed state proxies are a DX layer over the same replication engine. They delegate to `Get`, `Set`, `SetForPlayer`, `UpdateForPlayer`, and `Subscribe` using the field name as the state key.
:::

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
Riptide.Server.State:Set("matchPhase", "Intermission")
Riptide.Server.State:Set("serverTime", os.time())
```

---

### `SetForPlayer`

```lua
State:SetForPlayer(player: Player, key: string, value: any) -> ()
```

Sets a **player-scoped** state value. Only the target player receives the delta.

```lua
Riptide.Server.State:SetForPlayer(player, "coins", 500)
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
local newCoins = Riptide.Server.State:UpdateForPlayer(player, "coins", function(old)
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
local globalPhase = Riptide.Server.State:Get("matchPhase")
local playerCoins = Riptide.Server.State:Get("coins", player)
```

**Client** — ignores the `player` parameter. Resolves player-scoped first, then falls back to global:

```lua
local coins = Riptide.Client.State:Get("coins")
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
local unsubscribe = Riptide.Client.State:Subscribe("coins", function(value)
    coinLabel.Text = "Coins: " .. tostring(value or 0)
end)

-- Later, when no longer needed:
unsubscribe()
```

:::tip
Always call the unsubscribe function when the UI element or controller is destroyed to prevent memory leaks.
:::

:::note
The immediate callback may receive `nil` if the state hasn't been replicated yet (e.g., the server hasn't set the value, or the snapshot is still in transit). Always handle `nil` defensively:
```lua
Riptide.Client.State:Subscribe("coins", function(value)
    coinLabel.Text = "Coins: " .. tostring(value or 0)
end)
```
:::

---

### `RequestSync`

```lua
State:RequestSync() -> boolean
```

Manually requests a full state snapshot from the server. Called **automatically** on init, but can be invoked manually to force a re-sync.

The request is **asynchronous** — it fires an event to the server and applies the snapshot when the server responds. Deltas that arrive during the round-trip are buffered and replayed after the snapshot is applied.

Returns `true` if the request was dispatched, `false` if Network is unavailable, called on server, or a request is already in flight.

```lua
local sent = Riptide.Client.State:RequestSync()
if sent then
    print("Snapshot re-sync requested.")
end
```

---

## Sync Protocol

```
Client connects
  → FireServer("__riptide_state_snapshot")     [request]

Server responds
  → FireClient(player, "__riptide_state_snapshot", {
      global         = { ... },
      globalVersions = { ... },
      player         = { ... },
      playerVersions = { ... },
    })

After initial sync, deltas arrive as flat args:
  → FireAllClients("__riptide_state_delta", scope, key, value, version)
  → FireClient(player, "__riptide_state_delta", scope, key, value, version)

  scope   = "global" | "player"
  key     = string
  value   = any
  version = number (monotonically increasing per key per scope)
```

- Each key has a monotonically increasing **version** per scope.
- The client discards deltas with a version ≤ the current known version (idempotent).
- Deltas received during the snapshot round-trip are buffered and replayed in order after the snapshot is applied.
- On player leave, the server automatically cleans up all player-scoped state via `PlayerLifecycle`.

:::note
Subscribers registered via `Subscribe()` are notified **synchronously** when a delta or snapshot changes a key's resolved value. Callbacks must not yield — use `task.defer` internally if deferred execution is needed.
:::
