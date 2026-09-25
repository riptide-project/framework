---
slug: versions/0.7.1/api/state-replication
title: State replication
description: Server-authoritative state in Riptide 0.7.1.
---

`Riptide.State` stores state on the server and sends an initial snapshot plus later updates to clients. Use global keys for values everyone sees and player keys for private per-player values.

## Write state on the server

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Riptide = require(ReplicatedStorage.Packages.Riptide)

Riptide.State:Set("round", 1)

Players.PlayerAdded:Connect(function(player)
    Riptide.State:SetForPlayer(player, "coins", 100)
end)

local function awardCoins(player)
    Riptide.State:UpdateForPlayer(player, "coins", function(previous)
        return (previous or 0) + 10
    end)
end
```

Use `State:Get(key, player?)` on the server to read a key. `SetForPlayer` and `UpdateForPlayer` affect the named player; keep gameplay decisions and writes on the server.

## Observe state on the client

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Riptide = require(ReplicatedStorage.Packages.Riptide)

local unsubscribe = Riptide.State:Subscribe("coins", function(value)
    print("Coins:", value)
end)

-- Later, when this view is removed:
unsubscribe()
```

A client can also read its current value with `State:Get(key)`. Retain the unsubscribe function and call it when a UI or controller stops observing the key.

In 0.7.1, client versions are tracked separately for global and player scopes. Removing a player override falls back to the global value, and `Subscribe` calls its initial callback synchronously.

**Next:** [Read the networking guide](../network/) to see the messages beneath the framework API.

---

This page describes **Riptide 0.7.1**. Check the [original release guide](../../readme/) and [tagged source](https://github.com/riptide-project/framework/tree/v0.7.1) for release-specific details.
