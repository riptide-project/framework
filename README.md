<div align="center">

<img src="https://github.com/riptide-project/framework/raw/maelstrom/assets/riptide_banner_v4.png" alt="Riptide Banner" width="100%">

<br/>

<a href="https://github.com/riptide-project/framework"><img src="https://raw.githubusercontent.com/maneetoo/Roblox-OSS-Badges/refs/heads/main/Badges/Community/GitHub/link-github-repository.svg" alt="GitHub Repository" height="28"></a>
<a href="https://riptide-project.github.io/framework"><img src="https://raw.githubusercontent.com/maneetoo/Roblox-OSS-Badges/refs/heads/main/Badges/Roblox-Styled/Original/link-documentation.svg" alt="Documentation" height="28"></a>
<a href="https://github.com/riptide-project/framework/releases"><img src="https://raw.githubusercontent.com/maneetoo/Roblox-OSS-Badges/refs/heads/main/Badges/Community/GitHub/link-github-releases.svg" alt="GitHub Releases" height="28"></a>
<a href="CHANGELOG.md"><img src="https://raw.githubusercontent.com/maneetoo/Roblox-OSS-Badges/refs/heads/main/Badges/Roblox-Styled/Original/link-changelog.svg" alt="Changelog" height="28"></a>
<a href="https://pesde.dev/packages/riptide/core"><img src="https://raw.githubusercontent.com/maneetoo/Roblox-OSS-Badges/refs/heads/main/Badges/Community/Package/link-pesde.svg" alt="Pesde Package" height="28"></a>
<a href="https://wally.run/package/riptide/core"><img src="https://raw.githubusercontent.com/maneetoo/Roblox-OSS-Badges/refs/heads/main/Badges/Community/Package/link-wally.svg" alt="Wally Package" height="28"></a>
<a href="https://github.com/riptide-project/framework/actions"><img src="https://raw.githubusercontent.com/maneetoo/Roblox-OSS-Badges/refs/heads/main/Badges/Roblox-Styled/Original/link-tests.svg" alt="Tests" height="28"></a>

<br/>
<br/>

Riptide was built from the ground up for production Roblox games. It solves the most common architecture problems while remaining invisible, staying out of your way, and scaling elegantly.

</div>

> [!WARNING]
> **🌊 Maelstrom Build — Unstable**
>
> You are on the **Maelstrom** pre-release channel (`0.9.0-maelstrom.2`). Maelstrom is Riptide's unstable development branch — it ships on a separate Git branch, is **not production-tested**, and APIs may change without notice. If you need stability, pin a [stable release](https://github.com/riptide-project/framework/releases).

---

## ✨ Key Features

- 📅 **Deterministic Lifecycle:** Phased initialization (`Load` → `Init` → `Start`) ensures modules and plugins load in a predictable, race-free order.
- 🔌 **Framework-Layer Plugins:** Sandboxed plugins load before game modules, reach bounded `Start` readiness before gameplay starts, support dependency ordering, and stay isolated so third-party failures cannot bring down the framework.
- ⚡ **Zero-Allocation Signals:** A synchronous linked-list signal dispatcher with zero scheduler overhead and no per-fire thread creation.
- 📡 **Unified Networking:** Multiplexed `RemoteEvent` and `UnreliableRemoteEvent` networking with flat, closure-free middleware chains.
- 🛡️ **Typed Remote Validation:** Enforce client payload types at the network boundary via `Riptide.Network.RegisterTyped()` in server modules and composable `Guard` validators.
- 📦 **100% Strict Luau:** Written entirely with `--!strict`, exporting clean API interfaces for full autocomplete and type-checking.
- 🛠️ **Built-in Power:** Ships with Sleitnick's `Trove` resource tracker, `EventBus` pub/sub, `Guard` schema validators, `StateMachine`, `Async` utilities, and server-authoritative `State` replication.

---

## 📦 Installation

### Via Pesde (Recommended)

```bash
pesde add riptide/core
```

### Via Wally

```toml
[dependencies]
Riptide = "riptide/core@0.9.0-maelstrom.2"
```

### Manual (.rbxm)

Download `Riptide.rbxm` from the [Releases](https://github.com/riptide-project/framework/releases) page and place it inside `ReplicatedStorage`.

---

## 🏁 Quick Look

Riptide organizes your game logic into **Services** (server) and **Controllers** (client). Each module follows a clean lifecycle: modules are loaded first, `Init` runs synchronously, and `Start` runs asynchronously afterward.

```lua
-- ServerScriptService/Services/CoinsService.lua
--!strict
local CoinsService = {}

function CoinsService:Init(Riptide)
    -- Init runs synchronously. Register network handlers and grab
    -- references to other services here — everything is loaded but
    -- not yet started.
    Riptide.Network.RegisterTyped("BuyItem", {
        Riptide.Guard.String(50),       -- itemId:  string, max 50 chars
        Riptide.Guard.Number(0, 1000),  -- price:   number, 0–1000
    }, function(player, itemId, price)
        print(player.Name .. " bought " .. itemId .. " for " .. price .. " coins")
    end)
end

function CoinsService:Start(Riptide)
    -- Start runs in its own coroutine — safe to yield here.
    self.Trove = Riptide.Trove.new()
    print("CoinsService is running!")
end

function CoinsService:OnPlayerAdded(Riptide, player)
    Riptide.State:SetForPlayer(player, "coins", 0)
end

return CoinsService
```

**Launch the server** from a server script:

```lua
-- ServerScriptService/main.server.lua
local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Riptide = require(ReplicatedStorage.Packages.Riptide).Server

Riptide.Launch({
    ModulesFolder = ServerScriptService.Services,
})
```

**Launch the client** from a LocalScript:

```lua
-- StarterPlayerScripts/main.client.lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Riptide = require(ReplicatedStorage.Packages.Riptide).Client

Riptide.Launch({
    ModulesFolder = Players.LocalPlayer.PlayerScripts.Controllers,
})
```

---

## 🧪 Testing Architecture

Riptide ships with a **Hybrid Testing Architecture** built on [`frktest`](https://github.com/itsfrank/frktest):

- **CI / Development:** 100+ unit and integration tests run via [Lune](https://github.com/lune-org/lune) CLI in milliseconds — no Studio required.
- **Engine Integration:** The exact same suites compile and run inside a real Roblox DataModel for true Client/Server replication validation.

```bash
lune run test/lune/RunLuneTests.luau
```

---

## 📚 Documentation

Complete setup guides, API reference, and examples:

**[👉 Riptide Documentation](https://riptide-project.github.io/framework)**

---

## 📄 License

MIT — see [LICENSE](LICENSE).
