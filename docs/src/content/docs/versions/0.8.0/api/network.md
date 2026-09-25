---
slug: versions/0.8.0/api/network
title: Network
description: Unified event and request communication between client and server.
---


The `Network` module provides a unified communication layer over a single `RemoteEvent` and `RemoteFunction` pair. All networking goes through named string dispatchers — no manual remote management required.

Access via `Riptide.Network`.

## Types

```lua
type Callback = (...any) -> any
type Middleware = (...any) -> any

type NetworkAPI = {
    Register: (funcName: string, callback: Callback) -> (),
    Unregister: (funcName: string, callback: Callback) -> (),
    UseMiddleware: (scope: "server" | "client", middleware: Middleware) -> (),
    ClearMiddlewares: (scope: ("server" | "client")?) -> (),

    -- Server-only
    FireClient: ((player: Player, funcName: string, ...any) -> ())?,
    FireAllClients: ((funcName: string, ...any) -> ())?,
    UnreliableFireClient: ((player: Player, funcName: string, ...any) -> ())?,
    UnreliableFireAllClients: ((funcName: string, ...any) -> ())?,
    InvokeClient: ((player: Player, funcName: string, ...any) -> any)?,

    -- Client-only
    FireServer: ((funcName: string, ...any) -> ())?,
    UnreliableFireServer: ((funcName: string, ...any) -> ())?,
    InvokeServer: ((funcName: string, ...any) -> any)?,
}
```

---

## Shared Methods

### `Register`

```lua
Network.Register(funcName: string, callback: Callback) -> ()
```

Registers a handler for a named network event or request. Multiple handlers can be registered for the same name — all will be called for events, but only the **first** is used for invokes.

**Server example** — callback receives `player` as the first argument:

```lua
Riptide.Network.Register("PlayerJumped", function(player, height)
    print(player.Name .. " jumped " .. height .. " studs!")
end)
```

**Client example** — no player argument:

```lua
Riptide.Network.Register("ShowNotification", function(message)
    print("Server says:", message)
end)
```

:::note
For invoke handlers (`InvokeServer` / `InvokeClient`), only the **first** registered handler is called. If multiple handlers are registered, a warning is emitted.
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

Riptide.Network.Register("Ping", onPing)
-- Later...
Riptide.Network.Unregister("Ping", onPing)
```

---

### `UseMiddleware`

```lua
Network.UseMiddleware(scope: "server" | "client", middleware: Middleware) -> ()
```

Adds a middleware function to the processing pipeline. Middlewares execute **in order** of registration and must call `next(...)` to continue the chain.

**Server middleware signature:**

```lua
Riptide.Network.UseMiddleware("server", function(player, funcName, next, ...)
    -- Validate, rate-limit, log, etc.
    if not isAuthenticated(player) then
        return nil  -- block the request
    end
    return next(...)  -- continue to handler
end)
```

**Client middleware signature:**

```lua
Riptide.Network.UseMiddleware("client", function(funcName, next, ...)
    print("[Network] Received:", funcName)
    return next(...)
end)
```

:::caution
If a middleware does **not** call `next(...)`, the handler at the end of the chain will never execute. This is intentional for blocking (e.g., auth/rate-limit) middlewares.
:::

---

### `ClearMiddlewares`

```lua
Network.ClearMiddlewares(scope: ("server" | "client")?) -> ()
```

Clears all registered middlewares. If `scope` is `nil`, clears **both** server and client pipelines.

```lua
Riptide.Network.ClearMiddlewares("server")  -- server only
Riptide.Network.ClearMiddlewares()           -- both
```

---

## Server-Only Methods

These methods are only available when running on the server. Calling them on the client will error.

### `FireClient`

```lua
Network.FireClient(player: Player, funcName: string, ...any) -> ()
```

Fires a named event to a specific player.

```lua
Riptide.Network.FireClient(player, "DataLoaded", playerData)
```

### `FireAllClients`

```lua
Network.FireAllClients(funcName: string, ...any) -> ()
```

Broadcasts a named event to all connected players.

```lua
Riptide.Network.FireAllClients("GlobalNotification", "Double XP activated!")
```

### `UnreliableFireClient` / `UnreliableFireAllClients`

```lua
Network.UnreliableFireClient(player: Player, funcName: string, ...any) -> ()
Network.UnreliableFireAllClients(funcName: string, ...any) -> ()
```

Fires a named event over an `UnreliableRemoteEvent`. Perfect for high-frequency, non-critical data like particles, hitmarkers, or positional updates where dropped packets shouldn't stall the network.

```lua
Riptide.Network.UnreliableFireAllClients("PlayerRotated", player, CFrame.new())
```

:::tip
Unreliable events transparently route to the *same* `Register` callbacks. The receiving code doesn't need to know if the event was sent reliably or unreliably!
:::

### `InvokeClient`

```lua
Network.InvokeClient(player: Player, funcName: string, ...any) -> any
```

Invokes a handler on a specific client and returns the result. **Yields** until the client responds.

```lua
local clientFps = Riptide.Network.InvokeClient(player, "GetFPS")
```

:::caution
`InvokeClient` yields the calling thread and trusts client responses. Use with care in production — prefer event-based patterns when possible.
:::

---

## Client-Only Methods

These methods are only available on the client. Calling them on the server will error.

### `FireServer`

```lua
Network.FireServer(funcName: string, ...any) -> ()
```

Fires a named event to the server.

```lua
Riptide.Network.FireServer("RequestPurchase", itemId, quantity)
```

### `UnreliableFireServer`

```lua
Network.UnreliableFireServer(funcName: string, ...any) -> ()
```

Fires a named event to the server over an `UnreliableRemoteEvent`. Use for extremely frequent inputs (like aim direction).

```lua
Riptide.Network.UnreliableFireServer("UpdateAimDirection", Vector3.new(0, 1, 0))
```

### `InvokeServer`

```lua
Network.InvokeServer(funcName: string, ...any) -> any
```

Invokes a handler on the server and returns the result. **Yields** until the server responds.

```lua
local inventory = Riptide.Network.InvokeServer("GetInventory")
```

---

## Architecture

Under the hood, Riptide creates exactly **three** remotes inside the package:

```
Riptide/shared/Remotes/
├── EventDispatcher           (RemoteEvent)
├── UnreliableEventDispatcher (UnreliableRemoteEvent)
└── FunctionDispatcher        (RemoteFunction)
```

All named events and invokes are multiplexed through these instances using the `funcName` string as a discriminator. This eliminates `ReplicatedStorage` clutter and centralizes all network traffic.
