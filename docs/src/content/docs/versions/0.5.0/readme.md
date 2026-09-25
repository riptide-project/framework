---
slug: versions/0.5.0/readme
title: Historical 0.5.0 guide
description: The 0.5.0 release guide, adapted from its README.
---

:::caution[Historical documentation]
This guide is adapted from the v0.5.0 source. Its APIs and install commands apply to that release.
:::

Riptide is a lightweight, strictly-typed, and modular Roblox framework. It features phased initialization, safe dependency injection, a robust unified networking layer, and a shared ComponentService for managing tagged instances.

## 📦 Installation

> [!WARNING]
> `v0.5.0` is the last release with first-class Wally support.
> Starting from the next major cycle, Pesde is the primary package manager.

### Via Pesde (recommended)
Add Riptide to your `pesde.toml` dependencies:
```toml
[dependencies]
Riptide = { name = "riptide/core", version = "^0.5.0", target = "roblox" }
```

Then install dependencies:
```bash
pesde install
```

### Via Wally
Add Riptide to your `wally.toml`:
```toml
[dependencies]
Riptide = "thereplicatedfirst/riptide@^0.5.0"
```

### Manual
Download `Riptide.rbxm` from the [v0.5.0 release](https://github.com/riptide-project/framework/releases/tag/v0.5.0) and insert it as `ReplicatedStorage/Packages/Riptide`.

## 🏁 How to Start

Riptide does not start automatically. You must launch the framework from your own Server and Client entry points.

### Server Initialization (`main.server.lua`)
```lua
local Riptide = require(ReplicatedStorage.Packages.Riptide)
local MyServerModules = ServerScriptService:WaitForChild("MyServerModules")
local MySharedModules = ReplicatedStorage:WaitForChild("SharedModules")
local MyComponents = ReplicatedStorage:WaitForChild("Components") -- optional

Riptide.Server.Launch({
    ModulesFolder = MyServerModules, -- Folder or { Folder, ... }
    SharedModulesFolder = MySharedModules, -- optional: Folder or { Folder, ... }
    ComponentsFolder = MyComponents, -- optional
})
```

### Client Initialization (`main.client.lua`)
```lua
local Riptide = require(ReplicatedStorage.Packages.Riptide)
local MyClientModules = ReplicatedStorage:WaitForChild("MyClientModules")
local MySharedModules = ReplicatedStorage:WaitForChild("SharedModules")
local MyComponents = ReplicatedStorage:WaitForChild("Components") -- optional

Riptide.Client.Launch({
    ModulesFolder = { MyClientModules }, -- Folder or { Folder, ... }
    SharedModulesFolder = { MySharedModules }, -- optional: Folder or { Folder, ... }
    ComponentsFolder = MyComponents, -- optional
})
```

## 🚀 Module Lifecycle & Dependency Injection (DI)

Riptide completely eliminates the need for `require()` circles. Any `ModuleScript` inside your designated `ModulesFolder` will be automatically loaded into the Riptide Registry.

> [!NOTE]
> Services and Controllers are registered by canonical module ID (relative path from `ModulesFolder`, e.g. `Economy/PlayerData`).
> Short names are still supported as aliases when unique.

If two modules share the same short name, Riptide marks that alias as ambiguous and requires full canonical path lookups.

Examples:
- `Riptide.GetService("Economy/PlayerData")` ✅ always deterministic
- `Riptide.GetService("PlayerData")` ✅ only if alias is unique
- `Riptide.GetService("Data")` ⚠️ returns `nil` when alias is ambiguous

Methods are executed in strict phases:
1. **`Init(Riptide)`**: Called synchronously. Use this to `GetService` or `GetController` and set up your variables.
2. **`Start(Riptide)`**: Called asynchronously via `task.spawn`. All modules are fully initialized at this point, so it is safe to interact with them and run game logic.

### Example DI Module
```lua
--!strict
local RiptidePkg = require(ReplicatedStorage.Packages.Riptide)
type Riptide = RiptidePkg.Riptide

local PlayerState = {}

function PlayerState:Init(Riptide: Riptide)
    -- Easily inject other modules
    self.DataService = Riptide.GetService("DataService")

    -- Listen to the unified Network layer
    Riptide.Network.Register("PlayerJumped", function(player, height)
        print(player.Name .. " jumped " .. height .. " studs!")
    end)
end

function PlayerState:Start(Riptide: Riptide)
    self.DataService:GiveMoney(100)
end

return PlayerState
```

## 📡 Networking (`Riptide.Network`)

Riptide automatically creates a single RemoteEvent and RemoteFunction inside its own package under the hood. No `ReplicatedStorage` clutter!

As of `v0.4.0`, network event dispatch uses a reusable trampoline handler in the hot-path to reduce closure allocations during heavy event traffic.

**Client-Side API**
- `Network.Register(name, callback)`: Listen for server events.
- `Network.Unregister(name, callback)`: Remove a previously registered handler.
- `Network.FireServer(name, ...)`: Send event data to the server.
- `Network.InvokeServer(name, ...)`: Request data from the server.

**Server-Side API**
- `Network.Register(name, callback)`: Listen for client events. Callback automatically receives `player` as the first argument.
- `Network.Unregister(name, callback)`: Remove a previously registered handler.
- `Network.FireClient(player, name, ...)`: Send event data to a specific player.
- `Network.FireAllClients(name, ...)`: Broadcast event data to everyone.
- `Network.InvokeClient(player, name, ...)`: Request data from a client.

## 🧩 ComponentService (`Riptide.ComponentService`)

A shared (server & client) system for managing component objects linked to tagged Instances via `CollectionService`.

As of `v0.4.0`, ComponentService startup is idempotent: repeated `_start(...)` calls are ignored to prevent duplicated CollectionService listeners.

Each Component is a `ModuleScript` whose name matches the tag. It must expose a `new(instance)` constructor and optionally a `Destroy(self)` cleanup method.

### Example Component (`Lava.lua`)
```lua
local Lava = {}
Lava.__index = Lava

function Lava.new(instance: BasePart)
    local self = setmetatable({
        _instance = instance,
        _connection = nil :: RBXScriptConnection?,
    }, Lava)

    self._connection = instance.Touched:Connect(function(hit)
        local humanoid = hit.Parent and hit.Parent:FindFirstChild("Humanoid")
        if humanoid then
            (humanoid :: Humanoid):TakeDamage(10)
        end
    end)

    return self
end

function Lava:Destroy()
    if self._connection then
        self._connection:Disconnect()
        self._connection = nil
    end
end

return Lava
```

**API**
- `ComponentService:Get(instance)`: Get the first component attached to an instance.
- `ComponentService:Get(instance, tagName)`: Get a specific component by tag name.

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](https://github.com/riptide-project/framework/blob/v0.5.0/LICENSE) file for details.
