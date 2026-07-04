---
title: Server Service
description: A small server service using the injected server API, typed validation, and player state.
---

This example shows the recommended Maelstrom-2 shape for a server module. Server modules receive the side-specific server API in lifecycle hooks, so `Riptide.Network`, `Riptide.State`, and `Riptide.GetService` autocomplete server-only methods.

```lua
-- ServerScriptService/Services/CoinsService.lua
--!strict

local CoinsService = {}

function CoinsService:Init(Riptide)
	Riptide.Network.RegisterTyped("BuyItem", {
		Riptide.Guard.String(50),
		Riptide.Guard.Number(0, 1000),
	}, function(player: Player, itemId: string, price: number)
		local coins = Riptide.State:Get("coins", player) or 0
		if coins < price then
			return
		end

		Riptide.State:SetForPlayer(player, "coins", coins - price)
		print(player.Name .. " bought " .. itemId)
	end)
end

function CoinsService:OnPlayerAdded(Riptide, player: Player)
	Riptide.State:SetForPlayer(player, "coins", 100)
end

function CoinsService:OnPlayerRemoving(_Riptide, player: Player)
	print("Saving coins for", player.Name)
end

return CoinsService
```

Launch it from a server script:

```lua
-- ServerScriptService/main.server.lua
--!strict

local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Riptide = require(ReplicatedStorage.Packages.Riptide).Server

Riptide.Launch({
	ModulesFolder = ServerScriptService.Services,
})
```

`Init` should stay non-yielding. Put loops, `WaitForChild`, and async work in `Start` or player hooks.
