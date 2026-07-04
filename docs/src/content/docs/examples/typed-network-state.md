---
title: Typed Network and State
description: Field-based typed Network and State proxies for autocomplete-friendly client/server code.
---

Typed proxies are optional. They are useful when you want field autocomplete for known event names and state keys while keeping the dynamic string APIs available.

## Shared Types

Put shared type aliases in a module both sides can import.

```lua
-- ReplicatedStorage/SharedModules/GameContracts.lua
--!strict

export type NetworkEvents = {
	RequestPurchase: {
		FireServer: (itemId: string, price: number) -> (),
		FireClient: (player: Player, ok: boolean, message: string) -> (),
	},
}

export type StateSchema = {
	coins: number,
	level: number,
}

return {}
```

## Server

```lua
-- ServerScriptService/Services/ShopService.lua
--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Contracts = require(ReplicatedStorage.SharedModules.GameContracts)

type NetworkEvents = Contracts.NetworkEvents
type StateSchema = Contracts.StateSchema

local ShopService = {}

function ShopService:Init(Riptide)
	local Network = Riptide.Network.TypedServer<NetworkEvents>()
	local State = Riptide.State.TypedServer<StateSchema>()

	Riptide.Network.RegisterTyped("RequestPurchase", {
		Riptide.Guard.String(50),
		Riptide.Guard.Number(0, 1000),
	}, function(player: Player, itemId: string, price: number)
		local coins = State.coins:Get(player) or 0
		if coins < price then
			Network.RequestPurchase:FireClient(player, false, "Not enough coins")
			return
		end

		State.coins:SetForPlayer(player, coins - price)
		Network.RequestPurchase:FireClient(player, true, "Purchased " .. itemId)
	end)
end

return ShopService
```

## Client

```lua
-- StarterPlayerScripts/Controllers/ShopController.lua
--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Contracts = require(ReplicatedStorage.SharedModules.GameContracts)

type NetworkEvents = Contracts.NetworkEvents
type StateSchema = Contracts.StateSchema

local ShopController = {}

function ShopController:Start(Riptide)
	local Network = Riptide.Network.TypedClient<NetworkEvents>()
	local State = Riptide.State.TypedClient<StateSchema>()

	State.coins:Subscribe(function(coins: number?)
		print("Coins:", coins or 0)
	end)

	Network.RequestPurchase:FireServer("HealthPotion", 25)
end

return ShopController
```

Use `TypedServer<T>()` and `TypedClient<T>()` for autocomplete. Use the dynamic APIs when event names or state keys are generated at runtime.
