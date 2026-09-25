---
slug: versions/0.8.1/guides/project-structure
title: Project Structure
description: Recommended folder layout for Riptide projects.
---


A well-organized project keeps server, client, and shared code cleanly separated. Here is the recommended layout for a Riptide project.

## Folder Layout

```
game/
├── ReplicatedStorage/
│   ├── Packages/
│   │   └── Riptide/              ← installed by pesde
│   ├── SharedModules/            ← shared between server & client
│   │   ├── CurrencyConfig.lua
│   │   └── ItemDatabase.lua
│   └── Components/               ← ComponentService modules (shared)
│       ├── Lava.lua
│       └── Checkpoint.lua
│
├── ServerScriptService/
│   ├── main.server.lua           ← server entry point
│   └── Services/                 ← server-only modules
│       ├── DataService.lua
│       ├── Economy/
│       │   └── CoinsService.lua
│       └── MatchService.lua
│
└── StarterPlayer/
    └── StarterPlayerScripts/
        ├── main.client.lua       ← client entry point
        └── Controllers/          ← client-only modules
            ├── UIController.lua
            └── InputController.lua
```

## Key Conventions

| Folder | Purpose | Passed to |
|--------|---------|-----------|
| `Services/` | Server-only game logic (data, economy, combat). | `ModulesFolder` on server |
| `Controllers/` | Client-only UI and input logic. | `ModulesFolder` on client |
| `SharedModules/` | Code shared by both server and client. | `SharedModulesFolder` on both |
| `Components/` | `CollectionService`-based component classes. | `ComponentsFolder` on both |
| `Packages/` | External dependencies installed by pesde. | `require()` directly |

:::note
Shared modules are loaded **before** side-specific modules. This means services and controllers can safely depend on shared module code during their `Init` phase.
:::

## Entry Scripts

### Server (`main.server.lua`)

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Riptide = require(ReplicatedStorage.Packages.Riptide)

Riptide.Server.Launch({
    ModulesFolder = ServerScriptService.Services,
    SharedModulesFolder = ReplicatedStorage.SharedModules,
    ComponentsFolder = ReplicatedStorage.Components,
})
```

### Client (`main.client.lua`)

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Riptide = require(ReplicatedStorage.Packages.Riptide)

Riptide.Client.Launch({
    ModulesFolder = Players.LocalPlayer.PlayerScripts.Controllers,
    SharedModulesFolder = ReplicatedStorage.SharedModules,
    ComponentsFolder = ReplicatedStorage.Components,
})
```

## Multi-Folder Setup

Both `ModulesFolder` and `SharedModulesFolder` accept arrays of folders:

```lua
Riptide.Server.Launch({
    ModulesFolder = {
        ServerScriptService.Services,
        ServerScriptService.GameplayServices,
    },
    SharedModulesFolder = {
        ReplicatedStorage.SharedModules,
        ReplicatedStorage.LibModules,
    },
})
```

This is useful when your codebase grows beyond a single directory per concern.
