---
slug: versions/0.9.0-maelstrom.3/guides/getting-started
title: Getting Started
description: Install Riptide, write your first Service and Controller, and launch your game.
---


This guide covers the Maelstrom-3 preview. If you need the latest stable release, use [Riptide 0.8.2](/framework/versions/0.8.2/guides/quickstart/).

---

## 1. Installation

### Via Pesde (recommended)

Install [Pesde](https://docs.pesde.dev/installation/). In your game folder, run:

```bash
pesde init
pesde add riptide/core@0.9.0-maelstrom.3 --alias Riptide
pesde install
```

In `pesde init`, choose `roblox` and `pesde/scripts_rojo`. Result: `pesde.toml` lists Riptide, and `roblox_packages/Riptide` is ready to sync into `ReplicatedStorage.Packages`.

### Via Wally

Install [Wally](https://github.com/UpliftGames/wally#installation) and run `wally init` in your game folder. Add this line under `[dependencies]` in the generated `wally.toml`:

```toml
Riptide = "riptide/core@0.9.0-maelstrom.3"
```

Then run `wally install`. Result: `Packages/Riptide` is ready to sync into `ReplicatedStorage.Packages`. In the Rojo example below, change `"roblox_packages"` to `"Packages"`.

### Manual Installation (.rbxm)

Download `Riptide.rbxm` from the [Maelstrom-3 release](https://github.com/riptide-project/framework/releases/tag/v0.9.0-maelstrom.3) and insert it in Studio as `ReplicatedStorage/Packages/Riptide`. Omit the `Packages` mapping from the Rojo project below.

---

## 2. Rojo Project Setup

[Rojo](https://rojo.space) syncs your local code files into Roblox Studio. Install the Rojo CLI and Studio plugin, then create a `default.project.json` at the root of your project:

```json
{
  "name": "my-riptide-game",
  "tree": {
    "$className": "DataModel",
    "ReplicatedStorage": {
      "$className": "ReplicatedStorage",
      "Packages": {
        "$path": "roblox_packages"
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

Create `src/shared/` as well; it can stay empty for this first example. Run `rojo build -o game.rbxlx` to check that the project and installed package can be assembled before opening Studio.

---

## 3. Your First Service (Server)

In Riptide, server-side game logic lives in **Services** — plain Lua tables with special lifecycle methods.

Create `src/server/Services/HelloService.lua`:

```lua
--!strict
-- src/server/Services/HelloService.lua

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
    Riptide.Network.Register("ClientReady", function(player)
        Riptide.Network.FireClient(player, "ServerGreeting", "Hello, " .. player.Name .. "!")
    end)
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
--!strict
-- src/client/Controllers/HelloController.lua

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
--!strict
-- src/server/main.server.lua
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
--!strict
-- src/client/main.client.lua
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

In the **Output** window, look for messages like these. The order of the `Start` and player messages can vary because module `Start` hooks run asynchronously:

```
🌊 [Riptide] Server Initialization Started...
HelloService:Init — framework is setting up!
🌊 [Riptide] ✅ Server Start Phase Dispatched.
Welcome, Player1!
HelloService:Start — everything is ready!
```

And on the client:

```
🌊 [Riptide] Client Initialization Started...
🌊 [Riptide] ✅ Client Start Phase Dispatched.
HelloController started on the client!
Server says: Hello, Player1!
```

Congratulations — you have a working Riptide project! 🎉

---

## Next Steps

- **[Project Structure](../project-structure/)** — recommended folder layout for larger games.
- **[Module Lifecycle](../module-lifecycle/)** — understand the Load / Init / Start phases in depth.
- **[Network](../../api/network/)** — fire events between server and client.
- **[State Replication](../../api/state-replication/)** — server-authoritative state synced to clients.
- **[Plugins](../plugins/)** — extend the framework with modular, sandboxed plugins.
