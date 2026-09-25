---
slug: versions/0.4.0/guides/getting-started
title: Getting started with 0.4.0
description: Install and launch Riptide 0.4.0.
---

## 1. Install this release

### Install with Wally

In a new project, run `wally init`, add this dependency to the generated `wally.toml`, then run `wally install`:

```toml
[dependencies]
Riptide = "thereplicatedfirst/riptide@0.4.0"
```

Result: `wally install` creates the `Packages/` directory containing Riptide.

Alternatively, download `Riptide.rbxm` from the [v0.4.0 release](https://github.com/riptide-project/framework/releases/tag/v0.4.0) and insert it as `ReplicatedStorage/Packages/Riptide` in Studio.

## 2. Make the folders

Create these Roblox instances (or their equivalent in your Rojo project):

- `ReplicatedStorage/Packages/Riptide`: the installed package.
- `ServerScriptService/ServerModules`: your server `ModuleScript` files.
- `ReplicatedStorage/ClientModules`: your client `ModuleScript` files.
- `ServerScriptService/main.server.lua`: the server entry point.
- `StarterPlayer/StarterPlayerScripts/main.client.lua`: the client entry point.

If you use Rojo, map the Wally `Packages/` directory to `ReplicatedStorage.Packages`. The examples below assume your package is available at `ReplicatedStorage.Packages.Riptide`. Adjust the `require` path if you install it elsewhere.

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

**Next:** [Understand the module lifecycle](../module-lifecycle/) and [send your first network event](../../api/network/).

---

This page describes **Riptide 0.4.0**. Check the [original release guide](../../readme/) and [tagged source](https://github.com/riptide-project/framework/tree/v0.4.0) for release-specific details.
