---
title: Getting Started
description: Install Riptide, write your first Service and Controller, and launch your game.
---


Welcome to Riptide! This guide walks you through every step — from installation to your first working Service and Controller — with no prior framework experience required.

---

## 1. Installation

### Via Pesde (Recommended)

[Pesde](https://github.com/pesde-pkg/pesde) is the recommended Luau package manager. Install it by following the [Pesde docs](https://github.com/pesde-pkg/pesde#installation), then run:

```bash
pesde add riptide/core
```

Pesde places Riptide inside `luau_packages/`. You reference it from your Rojo project as a `Packages` folder in `ReplicatedStorage`.

### Via Wally

```toml
[dependencies]
Riptide = "riptide/core@0.9.0-maelstrom.2"
```

### Manual Installation (.rbxm)

Download `Riptide.rbxm` from the [latest release](https://github.com/riptide-project/framework/releases/latest) and drop it into `ReplicatedStorage/Packages/`.

---

## 2. Rojo Project Setup

[Rojo](https://rojo.space) syncs your local code files into Roblox Studio. Create a `default.project.json` at the root of your project:

```json
{
  "name": "my-riptide-game",
  "tree": {
    "$className": "DataModel",
    "ReplicatedStorage": {
      "$className": "ReplicatedStorage",
      "Packages": {
        "$path": "luau_packages"
      },
      "SharedModules": {
        "$path": "src/shared"
      }
    },
    "ServerScriptService": {
      "$className": "ServerScriptService",
      "main": {
        "$path": "src/server/main.server.lua"
      },
      "Services": {
        "$path": "src/server/Services"
      }
    },
    "StarterPlayer": {
      "$className": "StarterPlayer",
      "StarterPlayerScripts": {
        "$className": "StarterPlayerScripts",
        "main": {
          "$path": "src/client/main.client.lua"
        },
        "Controllers": {
          "$path": "src/client/Controllers"
        }
      }
    }
  }
}
```

This produces the following hierarchy inside Roblox Studio:

```
ReplicatedStorage/
├── Packages/           ← Riptide and other dependencies
└── SharedModules/      ← code used by both server and client

ServerScriptService/
├── main               ← server entry point (Script)
└── Services/          ← server-only modules (Folder)

StarterPlayer/StarterPlayerScripts/
├── main               ← client entry point (LocalScript)
└── Controllers/       ← client-only modules (Folder)
```

Create the matching local folders:

```
src/
├── shared/            ← SharedModules
├── server/
│   ├── main.server.lua
│   └── Services/
└── client/
    ├── main.client.lua
    └── Controllers/
```

---

## 3. Your First Service (Server)

In Riptide, server-side game logic lives in **Services** — plain Lua tables with special lifecycle methods.

Create `src/server/Services/HelloService.lua`:

```lua
-- src/server/Services/HelloService.lua
--!strict

local HelloService = {}

--[[
    Init(Riptide) — runs SYNCHRONOUSLY before any module starts.
    Use this phase to:
      • store references to other services
      • register network event handlers
      • set up initial state
    Do NOT yield here (no task.wait, no async calls).
]]
function HelloService:Init(Riptide)
    print("HelloService:Init — framework is setting up!")
end

--[[
    Start(Riptide) — runs ASYNCHRONOUSLY (via task.spawn) after ALL
    modules have finished Init. Use this phase to:
      • start game loops
      • connect to events
      • yield freely
]]
function HelloService:Start(Riptide)
    print("HelloService:Start — everything is ready!")
end

--[[
    OnPlayerAdded(Riptide, player) — called when a player joins.
    Also replays for players already in the server after module
    initialization and plugin readiness.
]]
function HelloService:OnPlayerAdded(Riptide, player)
    print("Welcome, " .. player.Name .. "!")
end

--[[
    OnPlayerRemoving(Riptide, player) — called when a player leaves.
    Use this to clean up player-specific data.
]]
function HelloService:OnPlayerRemoving(Riptide, player)
    print("Goodbye, " .. player.Name .. "!")
end

return HelloService
```

:::note[Colon vs. dot syntax]
Lifecycle methods (`Init`, `Start`, `OnPlayerAdded`, `OnPlayerRemoving`) are called with **colon syntax** — `self` (your module table) is automatically the first argument, and `Riptide` is the second.

Module lookup methods (`GetService`, `GetController`) are called with **dot syntax** — they are plain functions, not methods. Lifecycle hooks receive the side-specific Riptide API, so server services can call `Riptide.GetService` and client controllers can call `Riptide.GetController` directly:
```lua
-- ✅ Correct
local DataService = Riptide.GetService("DataService")

-- ❌ Wrong — passes Riptide as the name argument
local DataService = Riptide:GetService("DataService")
```
:::

---

## 4. Your First Controller (Client)

Client-side logic lives in **Controllers** — same idea, different folder.

Create `src/client/Controllers/HelloController.lua`:

```lua
-- src/client/Controllers/HelloController.lua
--!strict

local HelloController = {}

function HelloController:Init(Riptide)
    -- Listen for a network event fired by the server
    Riptide.Network.Register("ServerGreeting", function(message)
        print("Server says:", message)
    end)
end

function HelloController:Start(Riptide)
    -- Tell the server we are ready
    Riptide.Network.FireServer("ClientReady")
    print("HelloController started on the client!")
end

return HelloController
```

---

## 5. Launch Entry Scripts

Riptide does **not** start automatically. You must call `Launch` from both your server and client entry scripts.

### Server Entry Point

Create `src/server/main.server.lua`:

```lua
-- src/server/main.server.lua
--!strict
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

-- Require Riptide from the Packages folder
local Riptide = require(ReplicatedStorage.Packages.Riptide).Server

Riptide.Launch({
    -- Required: the Folder containing your server Services
    ModulesFolder = ServerScriptService.Services,

    -- Optional: shared modules loaded BEFORE Services
    SharedModulesFolder = ReplicatedStorage.SharedModules,
})
```

### Client Entry Point

Create `src/client/main.client.lua`:

```lua
-- src/client/main.client.lua
--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players           = game:GetService("Players")

local Riptide = require(ReplicatedStorage.Packages.Riptide).Client

Riptide.Launch({
    -- Required: the Folder containing your client Controllers
    ModulesFolder = Players.LocalPlayer.PlayerScripts.Controllers,

    -- Optional: shared modules loaded BEFORE Controllers
    SharedModulesFolder = ReplicatedStorage.SharedModules,
})
```

---

## 6. Start Rojo & Play

1. Run `rojo serve` in your terminal.
2. Connect via the Rojo Studio plugin.
3. Press **Play** in Roblox Studio.

You should see this in the **Output** window:

```
🌊 [Riptide] Server Initialization Started...
HelloService:Init — framework is setting up!
HelloService:Start — everything is ready!
🌊 [Riptide] ✅ Server Start Phase Dispatched.
Welcome, Player1!
```

And on the client:

```
🌊 [Riptide] Client Initialization Started...
HelloController started on the client!
🌊 [Riptide] ✅ Client Start Phase Dispatched.
```

Congratulations — you have a working Riptide project! 🎉

---

## Next Steps

- **[Project Structure](../project-structure/)** — recommended folder layout for larger games.
- **[Module Lifecycle](../module-lifecycle/)** — understand the Load / Init / Start phases in depth.
- **[Network](../../api/network/)** — fire events between server and client.
- **[State Replication](../../api/state-replication/)** — server-authoritative state synced to clients.
- **[Plugins](../plugins/)** — extend the framework with modular, sandboxed plugins.
