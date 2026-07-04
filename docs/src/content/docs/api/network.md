---
title: Network
description: Unified event communication between client and server.
---


The `Network` module provides a unified communication layer over a single `RemoteEvent` / `UnreliableRemoteEvent` pair. All networking goes through **named string dispatchers** — no manual remote management required.

> **Maelstrom breaking change:** `RemoteFunction`-based APIs (`InvokeClient`, `InvokeServer`) have been removed. Use `Riptide.Async` over paired `FireServer`/`FireClient` calls for request/response patterns instead.

Prefer side-specific access through `Riptide.Server.Network` or `Riptide.Client.Network`. The root `Riptide.Network` alias remains available for compatibility and dynamic shared code.

## Types

```lua
type Callback = (...any) -> any
type Middleware = (...any) -> any
type Validator = (value: any) -> (boolean, string?)

type NetworkBaseAPI = {
    Register: (funcName: string, callback: Callback) -> (),
    RegisterTyped: (funcName: string, validators: { Validator }, callback: Callback) -> (),
    RegisterTypedUnreliable: (funcName: string, validators: { Validator }, callback: Callback) -> (),
    Unregister: (funcName: string, callback: Callback) -> (),
    UseMiddleware: (scope: "server" | "client", middleware: Middleware) -> (),
    ClearMiddlewares: (scope: ("server" | "client")?) -> (),
}

type NetworkServerAPI = NetworkBaseAPI & {
    FireClient: (player: Player, funcName: string, ...any) -> (),
    FireAllClients: (funcName: string, ...any) -> (),
    UnreliableFireClient: (player: Player, funcName: string, ...any) -> (),
    UnreliableFireAllClients: (funcName: string, ...any) -> (),
    TypedServer: <TEvents>() -> TypedServer<TEvents>,
}

type NetworkClientAPI = NetworkBaseAPI & {
    FireServer: (funcName: string, ...any) -> (),
    UnreliableFireServer: (funcName: string, ...any) -> (),
    TypedClient: <TEvents>() -> TypedClient<TEvents>,
}
```

---

## Typed Event Proxies

Maelstrom-2 adds typed proxy factories for outbound events. They keep the dynamic string APIs available, but let Luau autocomplete event names as fields and check payloads from your event map.

### Client to Server

```lua
type ServerEvents = {
    PurchaseItem: (itemId: string, count: number) -> (),
    EquipItem: (itemId: string) -> (),
}

local Net = Riptide.Client.Network.TypedClient<ServerEvents>()

Net.PurchaseItem("sword", 1)
Net.EquipItem("sword")
```

At runtime this delegates to:

```lua
Riptide.Client.Network.FireServer("PurchaseItem", "sword", 1)
```

### Server to Client

```lua
type ClientEvents = {
    RewardPlayer: (player: Player, amount: number, reason: string) -> (),
}

local Net = Riptide.Server.Network.TypedServer<ClientEvents>()

Net.RewardPlayer(player, 100, "Quest")
```

At runtime this delegates to:

```lua
Riptide.Server.Network.FireClient(player, "RewardPlayer", 100, "Quest")
```

:::note
The typed proxy is a DX layer for outbound calls. Runtime validation still belongs at inbound boundaries through `RegisterTyped`, `RegisterTypedUnreliable`, and server middleware.
:::

---

## Shared Methods

### `Register`

```lua
Network.Register(funcName: string, callback: Callback) -> ()
```

Registers a handler for a named network event. Multiple handlers can be registered for the same name — all are called.

**Server example** — callback receives `player` as the first argument:

```lua
Riptide.Server.Network.Register("PlayerJumped", function(player, height)
    print(player.Name .. " jumped " .. height .. " studs!")
end)
```

**Client example** — no player argument:

```lua
Riptide.Client.Network.Register("ShowNotification", function(message)
    print("Server says:", message)
end)
```

---

### `RegisterTyped`

```lua
Network.RegisterTyped(funcName: string, validators: { (value: any) -> (boolean, string?) }, callback: Callback) -> ()
```

Like `Register`, but each argument from the client is validated against a matching `Guard` validator before the callback runs. If **any** argument fails, the event is silently dropped and a warning is logged — the callback never fires.

This is the recommended way to handle **any client-to-server event** where you care about data integrity.

```lua
-- Guard validators enforce types at the network boundary
Riptide.Server.Network.RegisterTyped("BuyItem", {
    Riptide.Guard.String(50),       -- arg1: itemId,  string max 50 chars
    Riptide.Guard.Number(0, 1000),  -- arg2: price,   number 0–1000
}, function(player, itemId, price)
    -- Only reaches here if both arguments passed validation
    print(player.Name, "buys", itemId, "for", price, "coins")
end)
```

:::tip
Combine with `UseMiddleware` for server-wide checks (authentication, rate limiting) that run before individual handlers.
:::

---

### `Unregister`

```lua
Network.Unregister(funcName: string, callback: Callback) -> ()
```

Removes a specific previously registered handler. Pass the exact function reference used in `Register`.

```lua
local function onPing(player, data)
    -- handle
end

Riptide.Server.Network.Register("Ping", onPing)
-- Later...
Riptide.Server.Network.Unregister("Ping", onPing)
```

---

### `UseMiddleware`

```lua
Network.UseMiddleware(scope: "server" | "client", middleware: Middleware) -> ()
```

Adds a middleware function to the processing pipeline. Middlewares run as a flat **for-loop** — no closures, no recursion. Each middleware receives the payload `args` table **by reference** and may mutate it in place.

**Server middleware signature:**

```lua
-- (player, funcName, args: {any}) -> boolean?
Riptide.Server.Network.UseMiddleware("server", function(player, funcName, args)
    if not isAuthenticated(player) then
        return false  -- return false to abort the chain
    end
    -- mutate args in-place if needed, e.g. args[1] = sanitize(args[1])
    -- return nothing (or true) to continue
end)
```

**Client middleware signature:**

```lua
-- (funcName, args: {any}) -> boolean?
Riptide.Client.Network.UseMiddleware("client", function(funcName, args)
    print("[Network] Received:", funcName)
    -- no return = continue chain
end)
```

:::caution
Returning `false` from a middleware **aborts the entire chain** — no subsequent middlewares or handlers will execute. Any other return value (including `nil`) allows the chain to continue.
:::

---

### `ClearMiddlewares`

```lua
Network.ClearMiddlewares(scope: ("server" | "client")?) -> ()
```

Clears all registered middlewares. If `scope` is `nil`, clears **both** server and client pipelines.

```lua
Riptide.Server.Network.ClearMiddlewares("server") -- server only
Riptide.Server.Network.ClearMiddlewares()         -- both
```

---

## Server-Only Methods

These methods are only available when running on the server.

### `FireClient`

```lua
Network.FireClient(player: Player, funcName: string, ...any) -> ()
```

Fires a named event to a specific player.

```lua
Riptide.Server.Network.FireClient(player, "DataLoaded", playerData)
```

### `FireAllClients`

```lua
Network.FireAllClients(funcName: string, ...any) -> ()
```

Broadcasts a named event to all connected players.

```lua
Riptide.Server.Network.FireAllClients("GlobalNotification", "Double XP activated!")
```

### `UnreliableFireClient` / `UnreliableFireAllClients`

```lua
Network.UnreliableFireClient(player: Player, funcName: string, ...any) -> ()
Network.UnreliableFireAllClients(funcName: string, ...any) -> ()
```

Fires a named event over an `UnreliableRemoteEvent`. Ideal for high-frequency, non-critical data like particles, hitmarkers, or positional updates.

```lua
Riptide.Server.Network.UnreliableFireAllClients("PlayerRotated", player, CFrame.new())
```

:::tip
Unreliable events route to the same `Register` callbacks. The receiving side doesn't need to know which transport was used.
:::

---

## Client-Only Methods

These methods are only available on the client.

### `FireServer`

```lua
Network.FireServer(funcName: string, ...any) -> ()
```

Fires a named event to the server.

```lua
Riptide.Client.Network.FireServer("RequestPurchase", itemId, quantity)
```

### `UnreliableFireServer`

```lua
Network.UnreliableFireServer(funcName: string, ...any) -> ()
```

Fires a named event to the server over an `UnreliableRemoteEvent`. Use for extremely frequent inputs (e.g., aim direction).

```lua
Riptide.Client.Network.UnreliableFireServer("UpdateAimDirection", Vector3.new(0, 1, 0))
```

---

## Architecture

Under the hood, Riptide creates exactly **two** remotes inside the package:

```
Riptide/shared/Remotes/
├── EventDispatcher           (RemoteEvent)
└── UnreliableEventDispatcher (UnreliableRemoteEvent)
```

All named events are multiplexed through these instances using the `funcName` string as a discriminator. This eliminates `ReplicatedStorage` clutter and centralizes all network traffic.

For request/response patterns (previously handled by `RemoteFunction`), use `Riptide.Async` over a pair of `FireServer`/`FireClient` events:

```lua
-- Server: respond to a client request
Riptide.Server.Network.Register("GetInventory", function(player)
    Riptide.Server.Network.FireClient(player, "GetInventory_Response", getPlayerInventory(player))
end)

-- Client: fire + wait for response
Riptide.Client.Network.FireServer("GetInventory")
local inventory = Riptide.Client.Network.Register("GetInventory_Response", function(data)
    -- handle data
end)
```
