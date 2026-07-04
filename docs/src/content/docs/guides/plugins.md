---
title: Plugins
description: Extend Riptide with modular plugins, shared cross-project logic, and sandboxed execution.
---

Plugins are modular extensions of the framework layer. They are designed for cross-project infrastructure (like data, permissions, anti-cheat, analytics, or shared component registration) that should be available to game modules without being embedded in game-specific code.

Plugins are treated as untrusted by default. Riptide isolates plugin hook failures, moves failed plugins to `Errored`, cleans sandbox-owned resources, and keeps the framework plus other plugins running.

---

## Plugin Structure

A Riptide plugin is a `ModuleScript` that returns a table with two main fields: `Descriptor` and `Hooks`.

```lua
--!strict
local MyPlugin = {}

MyPlugin.Descriptor = {
	Name = "MyPlugin",
	Version = "1.0.0",
	Description = "A simple example plugin.",
	Author = "Riptide Team",
	Side = "Shared", -- "Server", "Client", or "Shared"
	Dependencies = {}, -- Optional: list of plugin names to load first
	StartTimeout = 5, -- Optional: seconds allowed for Start readiness
	PublicAPI = {}, -- Optional: table exposed to other plugins and modules
}

MyPlugin.Hooks = {
	-- Required: Runs during framework initialization (synchronous)
	Init = function(self, sandbox)
		sandbox:Log("Plugin initialized!")
	end,

	-- Required: readiness gate before player lifecycle replay and game module Start
	Start = function(self, sandbox)
		sandbox:Log("Plugin started!")
	end,

	-- Optional: Runs immediately when the plugin is discovered
	OnRegister = function(self, sandbox) end,

	-- Optional: Runs when the plugin is stopped or destroyed
	Stop = function(self, sandbox) end,
	Destroy = function(self, sandbox) end,

	-- Optional: Player lifecycle hooks
	OnPlayerAdded = function(self, sandbox, player) end,
	OnPlayerRemoving = function(self, sandbox, player) end,
}

return MyPlugin
```

---

## Lifecycle Order

Plugins run before game modules become active:

```text
1. Core Riptide bootstrap
2. Plugin Load
3. Plugin Init
4. Game module Load
5. Game module Init
6. Plugin Start readiness barrier
7. Server PlayerLifecycle replay
8. Game module Start dispatch
```

Use `Init` to expose stable `PublicAPI` and register non-yielding framework extensions. `Init` must not yield.

Use `Start` for bounded readiness work that must complete before player replay and game module `Start`. `StartPlugins()` waits for each plugin's `Start` hook in dependency order. If a plugin takes longer than `Descriptor.StartTimeout` (default `5` seconds), it is marked `Errored`, sandbox resources are cleaned, and later plugins continue.

Long-running loops should be spawned inside `Start` instead of blocking the readiness gate:

```lua
function MyPlugin.Hooks:Start(sandbox)
	-- Do bounded setup here.
	sandbox:Log("Data cache is ready")

	task.spawn(function()
		while true do
			task.wait(60)
			-- background maintenance
		end
	end)
end
```

---

## The Plugin Sandbox

Every plugin receives a **Sandbox** object in its lifecycle hooks. This sandbox acts as a mediator, providing safe access to Riptide's core features while ensuring that if a plugin crashes, it doesn't bring down the entire framework.

The sandbox provides the following APIs:

### Network
- `sandbox:OnNetworkEvent(name, callback)`: Listen for a plugin-namespaced network event.
- `sandbox:FireClient(player, name, ...)`: Fire an event to a specific client.
- `sandbox:FireAllClients(name, ...)`: Fire an event to all clients.
- `sandbox:FireServer(name, ...)`: Fire an event to the server.

### State
- `sandbox:GetState(key, player?)`: Get global or player-specific state.
- `sandbox:SetState(key, value)`: Set global state (Server only).
- `sandbox:SetPlayerState(player, key, value)`: Set player state (Server only).
- `sandbox:SubscribeState(key, callback)`: Subscribe to state changes.

### Inter-Plugin Communication
- `sandbox:Emit(eventName, ...)`: Emit an event on the internal plugin bus.
- `sandbox:On(eventName, callback)`: Listen for an event on the internal plugin bus.
- `sandbox:Once(eventName, callback)`: Listen for the next matching event only.
- `sandbox:GetPluginAPI(pluginName)`: Access the `PublicAPI` table of another plugin.

The plugin bus uses the same dispatch implementation as `Riptide.EventBus`, including listener isolation and one-shot subscriptions. Plugin sandboxes intentionally expose only `Emit`, `On`, and `Once`; `Clear` and `Destroy` are framework-owned so one plugin cannot clear listeners registered by another plugin.

Normal plugins do not receive raw core event access such as `OnCoreEvent`. Use namespaced sandbox events instead. Trusted plugin permissions may be added later, but they are intentionally not part of the normal Maelstrom-2 sandbox.

### Utilities
- `sandbox:CreateSignal()`: Create a new tracked Signal.
- `sandbox:RunAsync(fn, timeout, ...)`: Run a function asynchronously with a timeout.
- `sandbox:Log(message)` / `sandbox:Warn(message)`: Namespaced logging.

---

## Registration

Plugins are registered via the `Launch` configuration. You can load plugins from a folder or pass them directly as a table.

### Via Folders

```lua
local Riptide = require(ReplicatedStorage.Packages.Riptide).Server

Riptide.Launch({
	ModulesFolder = ServerScriptService.Services,
	PluginsFolder = ServerScriptService.Plugins, -- Can be a Folder or {Folder}
})
```

### Via External Plugins

Useful for plugins that are already required or bundled as packages.

```lua
local Riptide = require(ReplicatedStorage.Packages.Riptide).Server
local MyPlugin = require(Packages.MyPlugin)

Riptide.Launch({
	ModulesFolder = ServerScriptService.Services,
	ExternalPlugins = { MyPlugin },
})
```

---

## Dependency Resolution

If your plugin depends on another plugin, list it in the `Descriptor.Dependencies` array. Riptide uses Kahn's algorithm to ensure plugins initialize and reach `Start` readiness in dependency order.

```lua
MyPlugin.Descriptor = {
	Name = "MyPlugin",
	Dependencies = { "CorePlugin" }, -- CorePlugin will Init and Start before MyPlugin
}
```

Missing required dependencies are strict in Maelstrom-2: the plugin is not loaded, and dependents of that blocked plugin are blocked as well. Optional dependencies are not yet a separate manifest field.

---

## Public API

Plugins can expose a public API that other plugins and game modules can access. Public APIs are typed as `{ [string]: unknown }` by default, or through `PluginDefinition<TPublicAPI>` when authoring a plugin with a known API shape.

```lua
MyPlugin.Descriptor = {
	Name = "MyPlugin",
	PublicAPI = {
		DoSomething = function()
			print("Doing something!")
		end,
	}
}
```

Other plugins can access this via `sandbox:GetPluginAPI("MyPlugin")`. Game modules receive the side-specific API, so they can access plugin entries through `Riptide.Plugins:GetPlugin("MyPlugin")`.

```lua
local entry = Riptide.Plugins:GetPlugin("MyPlugin")
local api = if entry then entry.descriptor.PublicAPI else nil
```
