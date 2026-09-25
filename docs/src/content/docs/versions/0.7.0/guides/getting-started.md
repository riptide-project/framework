---
slug: versions/0.7.0/guides/getting-started
title: Getting started with 0.7.0
description: Install and launch Riptide 0.7.0.
---

## 1. Install this release

### Install with Pesde

In your game folder, run `pesde init` and choose `roblox` and `pesde/scripts_rojo`. Then run:

```bash
pesde add riptide/core@0.7.0 --alias Riptide
pesde install
```

Result: `pesde.toml` lists Riptide, and the package is under `roblox_packages/`.


Alternatively, download `Riptide.rbxm` from the [v0.7.0 release](https://github.com/riptide-project/framework/releases/tag/v0.7.0) and insert it as `ReplicatedStorage/Packages/Riptide` in Studio.

## 2. Make the folders

Create these Roblox instances (or their equivalent in your Rojo project):

- `ReplicatedStorage/Packages/Riptide`: the installed package.
- `ServerScriptService/ServerModules`: your server `ModuleScript` files.
- `ReplicatedStorage/ClientModules`: your client `ModuleScript` files.
- `ServerScriptService/main.server.lua`: the server entry point.
- `StarterPlayer/StarterPlayerScripts/main.client.lua`: the client entry point.
- Optional `ReplicatedStorage/SharedModules`: modules loaded on both sides.

If you use Rojo, map Pesde’s `roblox_packages/` directory to `ReplicatedStorage.Packages`. The examples below assume your package is available at `ReplicatedStorage.Packages.Riptide`. Adjust the `require` path if you install it elsewhere.

## 3. Launch the server

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Riptide = require(ReplicatedStorage.Packages.Riptide)

Riptide.Server.Launch({
    ModulesFolder = ServerScriptService:WaitForChild("ServerModules"),
})
```

## 4. Launch the client

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Riptide = require(ReplicatedStorage.Packages.Riptide)

Riptide.Client.Launch({
    ModulesFolder = ReplicatedStorage:WaitForChild("ClientModules"),
})
```

Add `HelloService.lua` as a `ModuleScript` inside `ServerModules`:

```lua
local HelloService = {}

function HelloService:Init(riptide)
    print("HelloService initialized")
end

function HelloService:Start(riptide)
    print("HelloService started")
end

return HelloService
```

Run the game and check the server output for both messages. Riptide loads configured modules when the corresponding side calls `Launch`; it does not start itself.

Optional tagged components need a `ComponentsFolder` in the launch config. See [Tagged components](../../api/component-service/).

From 0.5.0 onward, `ModulesFolder` and optional `SharedModulesFolder` accept one folder or an array of folders. Shared folders load before side-specific folders. Add `SharedModulesFolder = ReplicatedStorage:WaitForChild("SharedModules")` to each launch config when you need shared modules.

**Next:** [Understand the module lifecycle](../module-lifecycle/) and [send your first network event](../../api/network/).

---

This page describes **Riptide 0.7.0**. Check the [original release guide](../../readme/) and [tagged source](https://github.com/riptide-project/framework/tree/v0.7.0) for release-specific details.
