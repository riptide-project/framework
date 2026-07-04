---
title: From Maelstrom-1
description: Migration checklist for moving from 0.9.0-maelstrom.1 to 0.9.0-maelstrom.2.
---

Use this page when you already adopted `0.9.0-maelstrom.1` and want to move to `0.9.0-maelstrom.2`.

## Package Version

```toml
[dependencies]
Riptide = "riptide/core@0.9.0-maelstrom.2"
```

## Riptide.Server and Riptide.Client

Maelstrom-2 exposes complete side-specific API tables. Entry scripts should import the side they launch, and module lifecycle hooks receive that side-specific API directly.

```lua
-- Before, inside a client controller
Riptide.Network.FireServer("RequestPurchase", itemId)
Riptide.State:Subscribe("coins", callback)

-- After, inside a client controller
Riptide.Network.FireServer("RequestPurchase", itemId)
Riptide.State:Subscribe("coins", callback)
```

```lua
-- StarterPlayerScripts/main.client.lua
local Riptide = require(ReplicatedStorage.Packages.Riptide).Client

Riptide.Launch({
	ModulesFolder = Players.LocalPlayer.PlayerScripts.Controllers,
})
```

The root package surface is kept for compatibility, but side imports plus injected side APIs give cleaner autocomplete and prevent server/client API overlap.

## Plugin Start Readiness

Maelstrom-1 had plugin `Start` as an async dispatch. Maelstrom-2 treats plugin `Start` as a readiness barrier.

```text
Plugin Load + Init
Game module Load
Game module Init
Plugin Start readiness
PlayerLifecycle replay
Game module Start
```

If a plugin `Start` yields forever, it will now block readiness until `Descriptor.StartTimeout` marks it `Errored`.

```lua
MyPlugin.Descriptor = {
	Name = "MyPlugin",
	Version = "0.1.0",
	Side = "Server",
	StartTimeout = 5,
}
```

Long-running work should be spawned inside `Start`:

```lua
function MyPlugin.Hooks:Start(sandbox)
	-- Bounded readiness work here.

	task.spawn(function()
		while true do
			task.wait(60)
			sandbox:Log("background tick")
		end
	end)
end
```

## Plugin Dependency Validation

Missing dependencies are strict. A plugin with a missing dependency is blocked, and plugins depending on that blocked plugin are blocked too.

```lua
MyPlugin.Descriptor = {
	Name = "NeedsProfiles",
	Dependencies = { "ProfilePlugin" },
}
```

If `ProfilePlugin` is not loaded, `NeedsProfiles` will not run.

## Plugin Sandbox Restrictions

Normal plugin sandboxes no longer expose raw core event APIs like `OnCoreEvent`. Use the supported sandbox APIs:

- `sandbox:OnNetworkEvent`
- `sandbox:FireClient`
- `sandbox:FireAllClients`
- `sandbox:FireServer`
- `sandbox:Emit`
- `sandbox:On`
- `sandbox:Once`
- `sandbox:GetPluginAPI`

## Async.Parallel Results

`Async.Parallel` now returns result objects.

```lua
local results = Riptide.Async.Parallel(tasks, 5)

if results[1].ok then
	print(results[1].value)
elseif results[1].timedOut then
	warn("task timed out")
else
	warn(results[1].error)
end
```

Update old code that expected raw return values.

## Typed Network Proxies

Use typed proxies for event-field autocomplete:

```lua
local Network = Riptide.Network.TypedServer<NetworkEvents>()
Network.PurchaseResult:FireClient(player, true, "ok")
```

The dynamic methods remain available:

```lua
Riptide.Network.FireClient(player, "PurchaseResult", true, "ok")
```

## Typed State Proxies

Use typed state proxies for key-level autocomplete:

```lua
local State = Riptide.State.TypedServer<StateSchema>()
State.coins:SetForPlayer(player, 100)
```

Dynamic string-key methods remain available.

## QA Runner Behavior

Studio QA runners now fail the whole run when a test module fails to require. If a test disappears from the pass count after migration, check the load phase logs first.

## Validation Checklist

- Import `.Server` / `.Client` in entry scripts and use the injected side API in modules.
- Audit plugin `Start` hooks for forever loops and move loops into spawned tasks.
- Add `Descriptor.StartTimeout` for plugins that do bounded async setup.
- Fix missing plugin dependencies instead of relying on silent skips.
- Update `Async.Parallel` result handling.
- Run Lune and Studio QA.
