---
slug: versions/0.6.0/api/network
title: Networking
description: Named events and requests in Riptide 0.6.0.
---

Riptide gives your code named messages over a shared `RemoteEvent` and request/response calls over a shared `RemoteFunction`. Use the API exposed as `Riptide.Network` on the side that sends or receives the message.

## Events

Register a server listener:

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Riptide = require(ReplicatedStorage.Packages.Riptide)

local function onPing(player, message)
    print(player.Name, message)
end

Riptide.Network.Register("Ping", onPing)
```

Send the event from a client script:

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Riptide = require(ReplicatedStorage.Packages.Riptide)

Riptide.Network.FireServer("Ping", "Hello from the client")
```

The server callback receives the sending `player` before the supplied arguments. Validate client data before using it in gameplay. Remove a listener with `Network.Unregister(name, callback)` when it is no longer needed.

## Available calls

| Client | Server |
| --- | --- |
| `Register(name, callback)` and `Unregister(name, callback)` | `Register(name, callback)` and `Unregister(name, callback)` |
| `FireServer(name, ...)` | `FireClient(player, name, ...)` and `FireAllClients(name, ...)` |
| `InvokeServer(name, ...)` | `InvokeClient(player, name, ...)` |

`Fire*` sends an event. `Invoke*` waits for a response from the other side; register a handler for that name first. Prefer events when no response is needed. Network methods use dot calls as shown above.

**Next:** [Connect this to a service](../../guides/module-lifecycle/).

---

This page describes **Riptide 0.6.0**. Check the [original release guide](../../readme/) and [tagged source](https://github.com/riptide-project/framework/tree/v0.6.0) for release-specific details.
