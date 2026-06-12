---
title: Project Structure
description: Recommended folder layout and conventions for Riptide projects of any size.
---


A well-organized project keeps server, client, and shared code cleanly separated so Riptide can load them in the right order. Here is the recommended layout for a small-to-medium game.

---

## Recommended Folder Layout

```
my-game/                        ← your repository root
│
├── luau_packages/              ← managed by pesde (don't edit manually)
│   └── Riptide/
│
├── src/
│   ├── shared/                 ← code shared by both server and client
│   │   ├── CurrencyConfig.lua
│   │   └── ItemDatabase.lua
│   │
│   ├── server/
│   │   ├── main.server.lua     ← SERVER entry point
│   │   └── Services/           ← server-only modules
│   │       ├── DataService.lua
│   │       ├── Economy/
│   │       │   └── CoinsService.lua
│   │       └── MatchService.lua
│   │
│   └── client/
│       ├── main.client.lua     ← CLIENT entry point
│       └── Controllers/        ← client-only modules
│           ├── UIController.lua
│           └── InputController.lua
│
└── default.project.json        ← Rojo project file
```

Inside Roblox Studio (after Rojo sync), this maps to:

```
ReplicatedStorage/
├── Packages/               ← luau_packages (Riptide lives here)
└── SharedModules/          ← src/shared

ServerScriptService/
├── main                    ← src/server/main.server.lua (Script)
└── Services/               ← src/server/Services/ (Folder)

StarterPlayer/StarterPlayerScripts/
├── main                    ← src/client/main.client.lua (LocalScript)
└── Controllers/            ← src/client/Controllers/ (Folder)
```

---

## Folder Purposes

| Folder | Where it lives in Studio | Passed to `Launch` as | Purpose |
|---|---|---|---|
| `Services/` | `ServerScriptService` | `ModulesFolder` (server) | Server-only logic — data, economy, combat |
| `Controllers/` | `StarterPlayerScripts` | `ModulesFolder` (client) | Client-only logic — UI, input, camera |
| `SharedModules/` | `ReplicatedStorage` | `SharedModulesFolder` (both) | Code used by both sides — configs, utilities |
| `Components/` | `ReplicatedStorage` (optional) | `ComponentsFolder` (both) | CollectionService component classes |
| `Packages/` | `ReplicatedStorage` | — | External dependencies (`require()` directly) |

:::note
Shared modules are **always loaded before** side-specific modules. This means your Services and Controllers can safely `require` or call shared utilities during their `Init` phase.
:::

---

## Entry Scripts

### Server — `src/server/main.server.lua`

```lua
--!strict
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Riptide = require(ReplicatedStorage.Packages.Riptide)

Riptide.Server.Launch({
    ModulesFolder       = ServerScriptService.Services,
    SharedModulesFolder = ReplicatedStorage.SharedModules,  -- optional
    ComponentsFolder    = ReplicatedStorage.Components,     -- optional
})
```

### Client — `src/client/main.client.lua`

```lua
--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players           = game:GetService("Players")

local Riptide = require(ReplicatedStorage.Packages.Riptide)

Riptide.Client.Launch({
    ModulesFolder       = Players.LocalPlayer.PlayerScripts.Controllers,
    SharedModulesFolder = ReplicatedStorage.SharedModules,  -- optional
    ComponentsFolder    = ReplicatedStorage.Components,     -- optional
})
```

:::tip
`SharedModulesFolder` and `ComponentsFolder` are both optional. Omit them if you don't use shared modules or CollectionService components yet.
:::

---

## Multi-Folder Setup

Both `ModulesFolder` and `SharedModulesFolder` accept an **array of folders**, making it easy to split large codebases across multiple directories:

```lua
Riptide.Server.Launch({
    ModulesFolder = {
        ServerScriptService.CoreServices,
        ServerScriptService.GameplayServices,
        ServerScriptService.AdminServices,
    },
    SharedModulesFolder = {
        ReplicatedStorage.SharedModules,
        ReplicatedStorage.LibModules,
    },
})
```

Modules from each folder are discovered in array order, then deduplicated.

---

## Adding a Component Folder

If you use `ComponentService` for CollectionService-based components, create a folder (e.g. `Components/`) in `ReplicatedStorage` and pass it via `ComponentsFolder`:

```
ReplicatedStorage/
└── Components/
    ├── Lava.lua        ← kills players on touch
    └── SpeedPad.lua    ← boosts player walk speed
```

```lua
Riptide.Server.Launch({
    ModulesFolder    = ServerScriptService.Services,
    ComponentsFolder = ReplicatedStorage.Components,
})
```

See the [Component Service](../../api/component-service/) reference for details.

---

## Next Steps

- **[Module Lifecycle](../module-lifecycle/)** — understand how Riptide loads and starts your modules.
- **[Network](../../api/network/)** — communicate between server and client.
