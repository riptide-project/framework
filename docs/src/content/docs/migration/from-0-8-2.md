---
title: From 0.8.2 Stable
description: Migration checklist for moving from the 0.8.2 stable release to 0.9.0-maelstrom.2.
---

Maelstrom-2 is a canary build. It intentionally includes breaking changes that improve type quality, plugin extensibility, network safety, and runtime determinism.

Use this page when migrating from the `0.8.2` stable release.

## Package Version

Update the package version:

```toml
[dependencies]
Riptide = "riptide/core@0.9.0-maelstrom.2"
```

## Side-Specific API

Entry scripts should import the side they launch. Modules then receive that same side-specific API in `Init`, `Start`, and player hooks.

```lua
-- Before, inside a server service
Riptide.Network.Register("Ping", callback)
local service = Riptide.GetService("DataService")
Riptide.State:SetForPlayer(player, "coins", 100)

-- After, inside a server service
Riptide.Network.Register("Ping", callback)
local service = Riptide.GetService("DataService")
Riptide.State:SetForPlayer(player, "coins", 100)
```

The difference is the value passed to the module: server modules receive `Riptide.Server`, and client modules receive `Riptide.Client`.

```lua
-- ServerScriptService/main.server.lua
local Riptide = require(ReplicatedStorage.Packages.Riptide).Server

Riptide.Launch({
	ModulesFolder = ServerScriptService.Services,
})
```

## Network Request/Response

If your 0.8.x code used `InvokeServer`, `InvokeClient`, or `RemoteFunction`-style APIs, migrate to explicit request/response events. Maelstrom networking is RemoteEvent-based to avoid blocking server threads on clients.

```lua
-- Server
Riptide.Network.RegisterTyped("RequestCoins", {}, function(player)
	local coins = Riptide.State:Get("coins", player) or 0
	Riptide.Network.FireClient(player, "CoinsResponse", coins)
end)

-- Client
Riptide.Network.Register("CoinsResponse", function(coins)
	print("Coins:", coins)
end)

Riptide.Network.FireServer("RequestCoins")
```

## Network Middleware

Middleware now receives the payload as a mutable args table. Return `false` to stop dispatch.

```lua
-- Server middleware
Riptide.Network.UseMiddleware(function(player, eventName, args)
	if eventName == "BuyItem" and typeof(args[2]) ~= "number" then
		return false
	end

	return true
end)
```

## Typed Network

Keep `RegisterTyped` for boundary validation. Add typed proxies when you want field autocomplete for known events.

```lua
local Network = Riptide.Network.TypedServer<NetworkEvents>()
Network.PurchaseResult:FireClient(player, true, "ok")
```

## State Replication

State remains server-authoritative, but Maelstrom-2 hardens malformed payload handling and adds typed key proxies.

```lua
local State = Riptide.State.TypedServer<StateSchema>()
State.coins:SetForPlayer(player, 100)
```

On the client:

```lua
local State = Riptide.State.TypedClient<StateSchema>()
State.coins:Subscribe(function(coins)
	print(coins or 0)
end)
```

## Async.Parallel

`Async.Parallel` now returns explicit result objects, so successful `nil`, thrown errors, and timeouts are distinguishable.

```lua
local results = Riptide.Async.Parallel({
	function()
		return "loaded"
	end,
	function()
		return nil
	end,
}, 5)

for _, result in ipairs(results) do
	if result.ok then
		print(result.value)
	elseif result.timedOut then
		warn("Timed out")
	else
		warn(result.error)
	end
end
```

## Plugins

Plugins are new framework-layer extensions. They load and initialize before game modules, then reach `Start` readiness before player replay and module `Start`.

```lua
Riptide.Launch({
	PluginsFolder = ServerScriptService.Plugins,
	ModulesFolder = ServerScriptService.Services,
})
```

Normal plugin sandboxes do not expose raw core event access such as `OnCoreEvent`. Use namespaced sandbox APIs like `sandbox:OnNetworkEvent`, `sandbox:Emit`, `sandbox:On`, `sandbox:Once`, and `sandbox:GetPluginAPI`.

## Lifecycle Order

The server startup order is now:

```text
1. Riptide bootstrap
2. Plugin Load + Init
3. Shared and server module Load
4. ComponentService start
5. Module Init
6. Plugin Start readiness
7. PlayerLifecycle replay
8. Module Start
```

Move code that must exist before services/controllers into plugin `Init`. Move bounded setup that must complete before gameplay into plugin `Start`.

## Luau Directives

Maelstrom-2 expects `--!strict` as the first line in source and test files. The test suite includes a directive policy check for this.

## Validation Checklist

- Import `.Server` / `.Client` in entry scripts and use the injected side API in modules.
- Replace any RemoteFunction request/response flow with event pairs.
- Update Network middleware signatures to args-table form.
- Update `Async.Parallel` callers to inspect result objects.
- Move framework extensions into plugins when they should be available before game modules start.
- Run Lune tests and Studio QA after migration.
