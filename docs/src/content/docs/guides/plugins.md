---
title: Plugins
description: Extend Riptide with modular plugins, shared cross-project logic, and sandboxed execution.
---

Plugins are modular extensions that run alongside your game modules. They are designed for cross-project logic (like an anti-cheat, a data store wrapper, or an analytics suite) that should remain isolated from your game-specific code.

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
	PublicAPI = {}, -- Optional: table exposed to other plugins and modules
}

MyPlugin.Hooks = {
	-- Required: Runs during framework initialization (synchronous)
	Init = function(self, sandbox)
		sandbox:Log("Plugin initialized!")
	end,

	-- Required: Runs after all modules and plugins have initialized (asynchronous)
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
- `sandbox:GetPluginAPI(pluginName)`: Access the `PublicAPI` table of another plugin.

### Utilities
- `sandbox:CreateSignal()`: Create a new tracked Signal.
- `sandbox:RunAsync(fn, timeout, ...)`: Run a function asynchronously with a timeout.
- `sandbox:Log(message)` / `sandbox:Warn(message)`: Namespaced logging.

---

## Registration

Plugins are registered via the `Launch` configuration. You can load plugins from a folder or pass them directly as a table.

### Via Folders

```lua
Riptide.Server.Launch({
	ModulesFolder = ServerScriptService.Services,
	PluginsFolder = ServerScriptService.Plugins, -- Can be a Folder or {Folder}
})
```

### Via External Plugins

Useful for plugins that are already required or bundled as packages.

```lua
local MyPlugin = require(Packages.MyPlugin)

Riptide.Server.Launch({
	ModulesFolder = ServerScriptService.Services,
	ExternalPlugins = { MyPlugin },
})
```

---

## Dependency Resolution

If your plugin depends on another plugin, list it in the `Descriptor.Dependencies` array. Riptide uses Kahn's algorithm to ensure plugins are initialized in the correct order.

```lua
MyPlugin.Descriptor = {
	Name = "MyPlugin",
	Dependencies = { "CorePlugin" }, -- CorePlugin will Init before MyPlugin
}
```

---

## Public API

Plugins can expose a public API that other plugins (and game modules) can access.

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

Other plugins can access this via `sandbox:GetPluginAPI("MyPlugin")`. Game modules can access it via `Riptide.Plugins:GetPlugin("MyPlugin").descriptor.PublicAPI`.
