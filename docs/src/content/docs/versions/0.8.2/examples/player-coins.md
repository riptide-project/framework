---
slug: versions/0.8.2/examples/player-coins
title: Player coins example
description: Replicate a server-owned coin value to a client controller.
---

This example builds on the [full server and client setup](../../guides/getting-started/). It uses **Riptide 0.8.2**.

## Server: initialize the player's value

Create `CoinsService` in your `Services` folder:

```lua
local CoinsService = {}

function CoinsService:OnPlayerAdded(Riptide, player)
    Riptide.State:SetForPlayer(player, "coins", 0)
end

return CoinsService
```

The server owns this value. `SetForPlayer` sends it only to the matching player's client. Use the `Riptide` argument directly in `OnPlayerAdded`: an already-connected player may be replayed before your service's `Init` method runs.

When your **server-side** game logic awards coins, update the value like this:

```lua
local newTotal = Riptide.State:UpdateForPlayer(player, "coins", function(oldValue)
    return (oldValue or 0) + 10
end)
```

The award decision should be made and validated on the server. Do not treat a client-reported coin total as authoritative.

## Client: react to changes

Create `CoinsController` in your `Controllers` folder:

```lua
local CoinsController = {}

function CoinsController:Init(Riptide)
    self.stopWatching = Riptide.State:Subscribe("coins", function(value)
        print("Coins:", value or 0)
    end)
end

return CoinsController
```

`Subscribe` calls your callback immediately with the current value, then again when a new value arrives. The first value may be `nil` while the initial snapshot is in transit, so the example displays `0` until it arrives. Call `self.stopWatching()` if you later remove the controller or its UI.

## What to explore next

- [State Replication](../../api/state-replication/) explains global and player-scoped values.
- [Network](../../api/network/) is for named events and requests rather than ongoing state.
- [Player Lifecycle](../../api/player-lifecycle/) explains why early player hooks use their `Riptide` argument.
